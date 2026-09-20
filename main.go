package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log"
	"os"
	"strconv"

	"github.com/overvenus/corplink-headless/pkg/headless"
	"github.com/overvenus/corplink-headless/pkg/proto"
)

var (
	rpcConf     = flag.String("rpc-conf", "./rpc.conf", "Path to rpc.conf file")
	companyCode = flag.String("company-code", "", "Company code for using Corplink")
	vpnServerID = flag.Int("vpn-server-id", -1, "VPN server ID")
	vpnMode     = flag.String("vpn-mode", "", "VPN server mode, split or full")
	debug       = flag.Bool("debug", false, "Enable debug mode")
)

func main() {
	flag.Parse()
	err := func() error {
		if *companyCode == "" {
			// Get from env
			code := os.Getenv("COMPANY_CODE")
			if code == "" {
				return errors.New("company-code must not be empty")
			}
			*companyCode = code
		}
		if *vpnServerID == -1 {
			// Get from env
			id := os.Getenv("VPN_SERVER_ID")
			if id != "" {
				var err error
				*vpnServerID, err = strconv.Atoi(id)
				if err != nil {
					return fmt.Errorf("invalid vpn-server-id: %w", err)
				}
			}
		}
		if *vpnMode == "" {
			// Get from env
			mode := os.Getenv("VPN_MODE")
			if mode == "" {
				mode = "split"
			}
			*vpnMode = mode
		}
		var vpnModePb proto.VpnMode
		switch *vpnMode {
		case "split":
			vpnModePb = proto.VpnMode_Split
		case "full":
			vpnModePb = proto.VpnMode_Full
		default:
			return fmt.Errorf("invalid vpn mode: %s", *vpnMode)
		}

		token, err := headless.NewToken(*rpcConf)
		if err != nil {
			return err
		}
		if *debug {
			log.Println("headless token:", token)
		}
		cli, err := headless.NewClient(headless.CorplinkServerAddr, *companyCode, *vpnServerID, vpnModePb, token, *debug)
		if err != nil {
			return err
		}

		ctx := context.Background()
		return cli.Run(ctx)
	}()
	if err != nil {
		log.Printf("%s", err)
	}
}
