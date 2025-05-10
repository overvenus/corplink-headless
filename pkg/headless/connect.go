package headless

import (
	"context"
	"fmt"
	"log"
	"time"

	"github.com/overvenus/corplink-headless/pkg/proto"
)

type connectState struct{}

func Connect() Step {
	return &connectState{}
}

func (s *connectState) connectVPN(ctx context.Context, cli State) error {
	resp, err := cli.ConnectVpn(ctx, &proto.ConnectVpnRequest{
		Server: -1, // -1 means auto
		Mode:   proto.VpnMode_Split,
	})
	if err != nil {
		return fmt.Errorf("failed to connectVPN: %w", err)
	}
	if resp.Code != 0 {
		return fmt.Errorf("failed to connectVPN: %s", resp.Message)
	}
	return nil
}

func GetVpnStatus(ctx context.Context, cli State) (bool, error) {
	resp, err := cli.GetVpnStatus(ctx, &proto.EmptyRequest{})
	if err != nil {
		return false, fmt.Errorf("failed to getVpnStatus: %w", err)
	}
	if resp.Code != 0 {
		return false, fmt.Errorf("failed to getVpnStatus: %s", resp.Message)
	}
	return resp.Data.Status == proto.VpnStatus_Connected, nil
}

func (s *connectState) Execute(ctx context.Context, cli State) error {
	if err := s.connectVPN(ctx, cli); err != nil {
		return fmt.Errorf("failed to connect: %w", err)
	}
	for range 10 {
		if connected, err := GetVpnStatus(ctx, cli); err != nil {
			return fmt.Errorf("failed to get VPN status: %w", err)
		} else if connected {
			log.Printf("VPN connected, company code: %s", cli.GetCompanyCode())
			break
		}
		time.Sleep(time.Second)
	}
	return nil
}
