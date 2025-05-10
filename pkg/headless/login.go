package headless

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"time"

	"github.com/overvenus/corplink-headless/pkg/proto"
	"github.com/skip2/go-qrcode"
)

type loginState struct{}

func Login() Step {
	return &loginState{}
}

//	{
//	    "code": 0,
//	    "action": "",
//	    "message": "",
//	    "data": {
//	        "name": "xxx",
//	        "zh_name": "xxx",
//	        "en_name": "xxx",
//	        "domain": "https://feilian.xxx.cn:3930",
//	        "enable_self_signed": false,
//	        "self_signed_cert": "",
//	        "enable_public_key": false,
//	        "public_key": "",
//	        "enable_spa": false,
//	        "spa_port": "",
//	        "enable_backup_domain": false,
//	        "backup_domain": ""
//	    }
//	}
type MatchResponse struct {
	Code    int    `json:"code"`
	Action  string `json:"action"`
	Message string `json:"message"`
	Data    struct {
		Name               string `json:"name"`
		ZhName             string `json:"zh_name"`
		EnName             string `json:"en_name"`
		Domain             string `json:"domain"`
		EnableSelfSigned   bool   `json:"enable_self_signed"`
		SelfSignedCert     string `json:"self_signed_cert"`
		EnablePublicKey    bool   `json:"enable_public_key"`
		PublicKey          string `json:"public_key"`
		EnableSpa          bool   `json:"enable_spa"`
		SpaPort            string `json:"spa_port"`
		EnableBackupDomain bool   `json:"enable_backup_domain"`
		BackupDomain       string `json:"backup_domain"`
	} `json:"data"`
}

func (s *loginState) matchCode(ctx context.Context, cli State) (*MatchResponse, error) {
	resp, err := cli.Http(ctx, &proto.HttpRequest{
		Method: "POST",
		Url:    "https://corplink.volcengine.cn/api/match?language=en",
		Data:   fmt.Sprintf("{\"code\":\"%s\"}", cli.GetCompanyCode()),
	})
	if err != nil {
		return nil, fmt.Errorf("failed to match %s: %w", cli.GetCompanyCode(), err)
	}
	if resp.Code != 0 {
		return nil, fmt.Errorf("failed to match %s: %s", cli.GetCompanyCode(), resp.Message)
	}
	match := &MatchResponse{}
	if err := json.Unmarshal([]byte(resp.Data), match); err != nil {
		return nil, fmt.Errorf("failed to unmarshal MatchResponse: %w", err)
	}
	if match.Code != 0 {
		return nil, fmt.Errorf("failed to match %s: %s", cli.GetCompanyCode(), match.Message)
	}
	return match, nil
}

func (s *loginState) setCompanyInfo(ctx context.Context, cli State, matchResp *MatchResponse) error {
	resp, err := cli.SetCompanyInfo(ctx, &proto.CompanyInfoRequest{
		Code:             cli.GetCompanyCode(),
		Name:             matchResp.Data.Name,
		Domain:           matchResp.Data.Domain,
		EnableSelfSigned: matchResp.Data.EnableSelfSigned,
		SelfSignedCert:   matchResp.Data.SelfSignedCert,
		EnablePublicKey:  matchResp.Data.EnablePublicKey,
		PublicKey:        matchResp.Data.PublicKey,
	})
	if err != nil {
		return fmt.Errorf("failed to setCompanyInfo %s: %w", cli.GetCompanyCode(), err)
	}
	if resp.Code != 0 {
		return fmt.Errorf("failed to setCompanyInfo %s: %s", cli.GetCompanyCode(), resp.Message)
	}
	return nil
}

func (s *loginState) probeLogin(ctx context.Context, cli State, matchResp *MatchResponse) (bool, error) {
	resp, err := cli.GetVpnList(ctx, &proto.EmptyRequest{})
	if err != nil {
		return false, fmt.Errorf("failed to probeLogin: %w", err)
	}
	return resp.Code == 0, nil
}

//	{
//	    "code": 0,
//	    "action": "",
//	    "message": "",
//	    "data": {
//	        "token": "AYYXXXyyyyZZZZxxxxxxUUUUUAAAAssssstcnNNN"
//	    }
//	}
type LoginResponse struct {
	Code    int    `json:"code"`
	Action  string `json:"action"`
	Message string `json:"message"`
	Data    struct {
		Token string `json:"token"`
	} `json:"data"`
}

func (s *loginState) loginToken(ctx context.Context, cli State) (string, error) {
	url, err := cli.Url("/api/login/token", nil)
	if err != nil {
		return "", fmt.Errorf("failed to get loginToken url: %w", err)
	}
	resp, err := cli.Http(ctx, &proto.HttpRequest{
		Method: "GET",
		Url:    url,
	})
	if err != nil {
		return "", fmt.Errorf("failed to loginToken %s: %w", cli.GetCompanyCode(), err)
	}
	if resp.Code != 0 {
		return "", fmt.Errorf("failed to loginToken %s: %s", cli.GetCompanyCode(), resp.Message)
	}
	login := &LoginResponse{}
	if err := json.Unmarshal([]byte(resp.Data), login); err != nil {
		return "", fmt.Errorf("failed to unmarshal LoginResponse: %w", err)
	}
	if login.Code != 0 {
		return "", fmt.Errorf("failed to loginToken %s: %s", cli.GetCompanyCode(), login.Message)
	}
	return login.Data.Token, nil
}

func (s *loginState) printLoginToken(ctx context.Context, cli State, token string) error {
	url, err := cli.Url("/api/token/verify/view", map[string]string{"token": token})
	if err != nil {
		return fmt.Errorf("failed to printLoginToken: %w", err)
	}
	qr, err := qrcode.New(url, qrcode.Low)
	if err != nil {
		return fmt.Errorf("failed to printLoginToken: %w", err)
	}

	fmt.Println("Please use Feilian App to scan the QR code:")
	fmt.Println(qr.ToSmallString(false))
	return nil
}

//	{
//	    "code": 0,
//	    "action": "",
//	    "message": "",
//	    "data": {
//	        "result": "success"
//	    }
//	}
type CheckLoginTokenResponse struct {
	Code    int    `json:"code"`
	Action  string `json:"action"`
	Message string `json:"message"`
	Data    struct {
		Result string `json:"result"`
	} `json:"data"`
}

func (s *loginState) checkLoginToken(ctx context.Context, cli State, token string) (bool, error) {
	url, err := cli.Url("/api/login/token/check", map[string]string{"token": token})
	if err != nil {
		return false, fmt.Errorf("failed to get checkLoginToken url: %w", err)
	}
	resp, err := cli.Http(ctx, &proto.HttpRequest{
		Method: "GET",
		Url:    url,
	})
	if err != nil {
		return false, fmt.Errorf("failed to verifyLoginToken %s: %w", cli.GetCompanyCode(), err)
	}
	if resp.Code != 0 {
		return false, fmt.Errorf("failed to verifyLoginToken %s: %s", cli.GetCompanyCode(), resp.Message)
	}
	verify := &CheckLoginTokenResponse{}
	if err := json.Unmarshal([]byte(resp.Data), verify); err != nil {
		return false, fmt.Errorf("failed to unmarshal checkLoginToken: %w", err)
	}
	if verify.Code != 0 {
		return false, fmt.Errorf("failed to verifyLoginToken %s: %s", cli.GetCompanyCode(), verify.Message)
	}
	return verify.Data.Result == "success", nil
}

func (s *loginState) Execute(ctx context.Context, cli State) error {
	hasLogin, err := func() (bool, error) {
		match, err := s.matchCode(ctx, cli)
		if err != nil {
			return false, err
		}
		log.Printf("match response: %s", match.Data.Domain)
		cli.SetCompanyDomain(match.Data.Domain)
		log.Printf("matched company code: %s company domain: %s", cli.GetCompanyCode(), match.Data.Domain)
		if err := s.setCompanyInfo(ctx, cli, match); err != nil {
			return false, err
		}
		return s.probeLogin(ctx, cli, nil)
	}()
	if err != nil {
		return fmt.Errorf("failed to login: %w", err)
	}
	if hasLogin {
		log.Printf("already login, company code: %s", cli.GetCompanyCode())
		return nil
	}
	for range 10 {
		token, err := s.loginToken(ctx, cli)
		if err != nil {
			return fmt.Errorf("failed to get login token: %w", err)
		}
		s.printLoginToken(ctx, cli, token)
		var err1 error
		var success bool
		for range 60 {
			success, err1 = s.checkLoginToken(ctx, cli, token)
			if success {
				log.Printf("login success, company code: %s", cli.GetCompanyCode())
				return nil
			}
			time.Sleep(time.Second)
		}
		log.Printf("failed to verify login token: %s", err1)
	}
	return fmt.Errorf("login failed, company code: %s", cli.GetCompanyCode())
}
