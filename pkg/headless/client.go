package headless

import (
	"context"
	"fmt"
	"net/url"

	"github.com/overvenus/corplink-headless/pkg/proto"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/metadata"
)

// CorplinkServerAddr is the address of the Corplink server.
// It seems to be hardcoded in the Corplink server.
const CorplinkServerAddr = "127.0.0.1:31055"

type Client struct {
	proto.CorpLinkClient
	token         Token
	companyCode   string
	companyDomain *url.URL
}

func NewClient(addr string, companyCode string, token Token, debug bool) (*Client, error) {
	// create gRPC connection
	opts := []grpc.DialOption{
		grpc.WithTransportCredentials(insecure.NewCredentials()),
	}
	if debug {
		opts = append(opts, grpc.WithUnaryInterceptor(unaryClientLoggerInterceptor))
	}
	conn, err := grpc.NewClient(CorplinkServerAddr, opts...)
	if err != nil {
		return nil, fmt.Errorf("failed to create gRPC connection: %w", err)
	}
	cli := proto.NewCorpLinkClient(conn)

	return &Client{
		CorpLinkClient: cli,
		token:          token,
		companyCode:    companyCode,
	}, nil
}

func (c *Client) GetCompanyCode() string {
	return c.companyCode
}

func (c *Client) SetCompanyDomain(companyDomain string) error {
	if c.companyDomain != nil {
		return fmt.Errorf("company domain is set: %s", c.companyDomain.String())
	}
	baseUrl, err := url.Parse(companyDomain)
	if err != nil {
		return fmt.Errorf("failed to parse company domain: %w", err)
	}
	// Add query parameters to the base URL
	//
	// ?app_version=2.0.9&brand=&build_number=615&language=en&model=&os=Linux&os_version=Ubuntu+20.04.6+LTS
	q := baseUrl.Query()
	for k, v := range map[string]string{
		"app_version":  "2.0.9",
		"brand":        "",
		"build_number": "615",
		"language":     "en",
		"model":        "",
		"os":           "Linux",
		"os_version":   "Ubuntu 20.04.6 LTS",
	} {
		q.Add(k, v)
	}
	baseUrl.RawQuery = q.Encode()
	c.companyDomain = baseUrl
	return nil
}

func (c *Client) Url(path string, queries map[string]string) (string, error) {
	if c.companyDomain == nil {
		return "", fmt.Errorf("company domain is not set")
	}
	url := c.companyDomain.JoinPath(path)
	q := url.Query()
	for k, v := range queries {
		q.Add(k, v)
	}
	url.RawQuery = q.Encode()
	return url.String(), nil
}

func (c *Client) Run(ctx context.Context) error {
	md := metadata.New(map[string]string{
		"corplink-user":  c.token.CorplinkUser,
		"corplink-token": c.token.CorplinkToken,
	})
	ctx = metadata.NewOutgoingContext(ctx, md)

	steps := []Step{
		Login(),
		Connect(),
		WaitExit(),
		Disconnect(),
	}
	for _, step := range steps {
		if err := step.Execute(ctx, c); err != nil {
			return fmt.Errorf("failed to execute step %T: %w\n", step, err)
		}
	}
	return nil
}

type State interface {
	proto.CorpLinkClient
	GetCompanyCode() string
	SetCompanyDomain(companyDomain string) error
	Url(path string, queries map[string]string) (string, error)
}

type Step interface {
	Execute(context.Context, State) error
}
