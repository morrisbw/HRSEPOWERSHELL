# ========================================
# SAFESEARCH FORTRESS — MULTI-GOOGLE EDITION
# Covers google.com, google.co.uk, google.com.au, google.ca, google.fr, google.de...
# Apex (@) + www, SafeScope + default.
# Forces records every time. No mercy.
# ========================================

# -------------------------------
# Define SafeSearch subnets
# -------------------------------
$safeSubnetsList = @(
    "192.168.1.0/23",
    "192.168.3.0/23",
    "1192.168.5.0/23"
    # You can use any subnets you like here as long as you list them in CIDR notation
    # and don't forget to remove the last comma if you are concatting from excel like i do
)

# -------------------------------
#  Create/Update SafeSubnets
# -------------------------------
if (Get-DnsServerClientSubnet -Name "SafeSubnets" -ErrorAction SilentlyContinue) {
    Write-Host "Updating 'SafeSubnets'..."
    Set-DnsServerClientSubnet -Name "SafeSubnets" -IPv4Subnet $safeSubnetsList
} else {
    Write-Host "Creating 'SafeSubnets'..."
    Add-DnsServerClientSubnet -Name "SafeSubnets" -IPv4Subnet $safeSubnetsList
}

# -------------------------------
# Zones to manage (APEX ONLY)
# -------------------------------
$zones = @(
    "google.com",
    "google.com.au",
    "google.co.uk",
    "google.ca",
    "google.fr",
    "google.de",
    "youtube.com",
    "bing.com"
)

foreach ($zone in $zones) {
    if (-not (Get-DnsServerZone -Name $zone -ErrorAction SilentlyContinue)) {
        Write-Host "Creating zone: $zone"
        Add-DnsServerPrimaryZone -Name $zone -ZoneFile "$zone.dns"
    } else {
        Write-Host "Zone exists: $zone"
    }
}

# -------------------------------
# Ensure both scopes: SafeScope + default
# -------------------------------
foreach ($zone in $zones) {
    foreach ($scope in @("SafeScope", "default")) {
        if (-not (Get-DnsServerZoneScope -ZoneName $zone -Name $scope -ErrorAction SilentlyContinue)) {
            Add-DnsServerZoneScope -ZoneName $zone -Name $scope
            Write-Host "$scope created in $zone"
        } else {
            Write-Host "$scope exists in $zone"
        }
    }
}

# -------------------------------
# Define IPs
# -------------------------------
$defaultIPs = @{
    "google.com"     = "142.250.72.46"
    "google.com.au"  = "142.250.72.46"
    "google.co.uk"   = "142.250.72.46"
    "google.ca"      = "142.250.72.46"
    "google.fr"      = "142.250.72.46"
    "google.de"      = "142.250.72.46"
    "youtube.com"    = "142.250.72.238"
    "bing.com"       = "204.79.197.200"
}

$bingStrictIP = "204.79.197.220"
$googleSafeIP = "216.239.38.120"

# -------------------------------
#  FORCE apex (@) and www in BOTH scopes
# -------------------------------
foreach ($zone in $zones) {
    foreach ($scope in @("default", "SafeScope")) {

        # Decide apex IP:
        if ($zone -eq "bing.com") {
            if ($scope -eq "default") {
                $apexIP = $defaultIPs[$zone]
            } else {
                $apexIP = $bingStrictIP
            }
        } else {
            if ($scope -eq "default") {
                $apexIP = $defaultIPs[$zone]
            } else {
                $apexIP = $googleSafeIP
            }
        }

        # FORCE apex @:
        Remove-DnsServerResourceRecord -ZoneName $zone -ZoneScope $scope -RRType "A" -Name "@" -Force -ErrorAction SilentlyContinue
        Add-DnsServerResourceRecord -ZoneName $zone -ZoneScope $scope -A -Name "@" -IPv4Address $apexIP
        Write-Host "$scope @.$zone -> $apexIP"

        # Decide www IP or CNAME:
        if ($zone -eq "bing.com") {
            if ($scope -eq "default") {
                # www for Bing default = A
                Remove-DnsServerResourceRecord -ZoneName $zone -ZoneScope $scope -RRType "A" -Name "www" -Force -ErrorAction SilentlyContinue
                Add-DnsServerResourceRecord -ZoneName $zone -ZoneScope $scope -A -Name "www" -IPv4Address $defaultIPs[$zone]
                Write-Host "$scope www.$zone -> $($defaultIPs[$zone])"
            } else {
                # www for Bing SafeScope = CNAME
                Remove-DnsServerResourceRecord -ZoneName $zone -ZoneScope $scope -RRType "CNAME" -Name "www" -Force -ErrorAction SilentlyContinue
                Add-DnsServerResourceRecord -ZoneName $zone -ZoneScope $scope -CName -Name "www" -HostNameAlias "strict.bing.com"
                Write-Host "$scope www.$zone -> strict.bing.com"
            }
        } else {
            if ($scope -eq "default") {
                $wwwIP = $defaultIPs[$zone]
            } else {
                $wwwIP = $googleSafeIP
            }
            Remove-DnsServerResourceRecord -ZoneName $zone -ZoneScope $scope -RRType "A" -Name "www" -Force -ErrorAction SilentlyContinue
            Add-DnsServerResourceRecord -ZoneName $zone -ZoneScope $scope -A -Name "www" -IPv4Address $wwwIP
            Write-Host "$scope www.$zone -> $wwwIP"
        }

    }
}

# -------------------------------
# Query Resolution Policies
# -------------------------------
$eqSafe = "EQ,SafeSubnets"
$neSafe = "NE,SafeSubnets"

foreach ($zone in $zones) {
    $prefix = ($zone -split "\.")[0]
    $prefix = $prefix.Substring(0,1).ToUpper() + $prefix.Substring(1)

    $safePolicy = "${prefix}SafePolicy"
    $normalPolicy = "${prefix}NormalPolicy"

    if (-not (Get-DnsServerQueryResolutionPolicy -ZoneName $zone -Name $safePolicy -ErrorAction SilentlyContinue)) {
        Add-DnsServerQueryResolutionPolicy -Name $safePolicy `
            -Action ALLOW `
            -ClientSubnet $eqSafe `
            -ZoneName $zone `
            -ZoneScope "SafeScope,1" `
            -ProcessingOrder 1
        Write-Host "$safePolicy created for $zone"
    } else {
        Write-Host "$safePolicy exists for $zone"
    }

    if (-not (Get-DnsServerQueryResolutionPolicy -ZoneName $zone -Name $normalPolicy -ErrorAction SilentlyContinue)) {
        Add-DnsServerQueryResolutionPolicy -Name $normalPolicy `
            -Action ALLOW `
            -ClientSubnet $neSafe `
            -ZoneName $zone `
            -ZoneScope "default,1" `
            -ProcessingOrder 2
        Write-Host "$normalPolicy created for $zone"
    } else {
        Write-Host "$normalPolicy exists for $zone"
    }
}

# -------------------------------
# Done & Bulletproof
# ish - Don't forget you must used firewall rules to stop these kidddds from making this pointless
# -------------------------------
