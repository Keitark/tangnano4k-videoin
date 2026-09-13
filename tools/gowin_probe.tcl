# Read-only device-database probe; this is not a SoftPHY eligibility test.
foreach part {
    GW1NSR-LV4CQN48PC7/I6
    GW1NSR-LV4CQN48PC6/I5
} {
    puts "=== $part ==="
    if {[catch {set_device -name GW1NSR-4C $part} result]} {
        puts "ERROR: $result"
    } else {
        puts "DEVICE_DATABASE_OK: $result"
    }
}
puts "Native HS still requires the physical FPGA to be C7/I6 or faster."
exit
