Name             = "connectivity"
NamePretty       = "Connectivity"
Icon             = "network-wireless"
Cache            = false
HideFromProviderlist = true

local WALKER  = os.getenv("HOME") .. "/.config/mango/scripts/walker/walker.sh"
local NETWORK = os.getenv("HOME") .. "/.config/mango/scripts/menus/network-menu.sh"
local VPN     = os.getenv("HOME") .. "/.config/mango/scripts/menus/vpn-menu.sh"

function GetEntries()
    return {
        {
            Text     = "Network",
            Subtext  = "Wi-Fi & connections",
            Icon     = "network-wireless",
            Keywords = {"network", "wifi", "wireless", "internet", "connection"},
            Actions  = { default = "sleep 0.05 && " .. NETWORK },
        },
        {
            Text     = "VPN",
            Subtext  = "WireGuard & OpenVPN",
            Icon     = "network-vpn",
            Keywords = {"vpn", "wireguard", "openvpn", "tunnel"},
            Actions  = { default = "sleep 0.05 && " .. VPN },
        },
        {
            Text     = "Bluetooth",
            Subtext  = "Devices & pairing",
            Icon     = "bluetooth",
            Keywords = {"bluetooth", "bt", "pair", "device"},
            Actions  = { default = "sleep 0.05 && " .. WALKER .. " -m bluetooth" },
        },
    }
end
