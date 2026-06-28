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

func (s *connectState) listVPN(ctx context.Context, cli State) error {
	resp, err := cli.GetVpnList(ctx, &proto.EmptyRequest{})
	if err != nil {
		return fmt.Errorf("failed to connectVPN: %w", err)
	}
	log.Printf("VPN list: %s", resp)
	return nil
}

func (s *connectState) connectVPN(ctx context.Context, cli State) error {
	resp, err := cli.ConnectVpn(ctx, &proto.ConnectVpnRequest{
		Server: int32(cli.GetVPNServerID()), // -1 means auto
		Mode:   cli.GetVPNMode(),
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
	if err := s.listVPN(ctx, cli); err != nil {
		return fmt.Errorf("failed to listVPN: %w", err)
	}
	if err := s.connectVPN(ctx, cli); err != nil {
		return fmt.Errorf("failed to connect: %w", err)
	}
	for range 10 {
		if connected, err := GetVpnStatus(ctx, cli); err != nil {
			return fmt.Errorf("failed to get VPN status: %w", err)
		} else if connected {
			log.Printf("%s VPN connected, company code: %s", time.Now().Format(time.DateTime), cli.GetCompanyCode())
			break
		}
		time.Sleep(time.Second)
	}
	return nil
}
