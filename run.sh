export BSCAPIKEY=JVYDFVBPD39X81YIVBGB4CXUIC9D1SVQF4
# Test3
# export PRIVATEKEY=21729659df493f5847157c4c77a92e5a468dae0211c37ff76e51f12b66f55819
#Paul
# export PRIVATEKEY=5de00ed0c8fecd374dd6736e3a1ec2fa995dc32e833313df256712db99bc8cbe
# 0x20f183F8F82042bB9acbd580e2d78C40f62a22A2
npx hardhat compile
npx hardhat run ./scripts/deploy.js --network testnet
npx hardhat verify --network testnet <contract address>