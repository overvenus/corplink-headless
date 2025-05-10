package main

import (
	"context"
	"flag"
	"log"

	"github.com/overvenus/corplink-headless/pkg/headless"
)

var rpcConf = flag.String("rpc-conf", "./rpc.conf", "Path to rpc.conf file")
var companyCode = flag.String("company-code", "", "Company code for using Corplink")
var debug = flag.Bool("debug", false, "Enable debug mode")

func main() {
	flag.Parse()
	err := func() error {
		if *companyCode == "" {
			log.Println("company-code is not be empty")
		}
		token, err := headless.NewToken(*rpcConf)
		if err != nil {
			return err
		}
		if *debug {
			log.Println("headless token:", token)
		}
		cli, err := headless.NewClient(headless.CorplinkServerAddr, *companyCode, token, *debug)
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
