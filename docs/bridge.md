# LANE OMNICHAIN BRIDGE DEVELOPMENT

## LANE BRIDGE — HOW IT WORKS

LANE uses the OFT (Omnichain Fungible Token) standard, which allows the same token to be transferred between different blockchain networks. The mechanism uses a burn (BURN) on the origin network and a mint (MINT) of the same amount on the destination network.

When a user sends 100 LANE from one network to another, the following occurs during the process.

### ORIGIN NETWORK

100 LANE are sent

↓

🔥 BURN

↓

The 100 LANE cease to exist on the origin network.

↓

### LAYERZERO V2

LayerZero V2 processes and delivers the cross-chain transfer message to the destination network.

↓

### DESTINATION NETWORK

⚡ MINT

↓

100 LANE are minted.

↓

The 100 LANE are credited to the recipient's wallet.

### RESULT

Origin: -100 LANE

Destination: +100 LANE

Global supply remains 21,000,000 LANE.

### TRANSFERRING LANE AGAIN

If those 100 LANE are later sent to another network, the same process occurs again:

🔥 BURN ON ORIGIN

↓

📨 TRANSFER MESSAGE THROUGH LAYERZERO V2

↓

⚡ MINT ON DESTINATION

This mechanism allows LANE to move between networks without duplicating the global token supply.
