import Foundation
import Combine

let fixture = """
,bytes_in,bytes_out,
old.1,99999999,99999999,
,bytes_in,bytes_out,
com.example.helper.42,2048,12,
uploader.43,10,4096,
idle.44,0,0,
invalid.45,nan,inf,
malformed
"""
let rows = ProcessTrafficParser.parse(fixture)!
assert(rows.count == 3)
assert(rows[0].name == "com.example.helper")
assert(rows[0].bytesIn == 2048)
assert(ProcessTraffic.top(rows, direction: .down).first?.id == 42)
assert(ProcessTraffic.top(rows, direction: .up).first?.id == 43)
assert(ProcessTraffic.top(rows, direction: .up).count == 2)
assert(ProcessTrafficParser.parse(",bytes_in,bytes_out,\nold.1,100,100,") == nil)
assert(ProcessTrafficParser.parse(",bytes_in,bytes_out,\n,bytes_in,bytes_out,\n")?.isEmpty == true)
let many = (1...10).map { ProcessTraffic(id: Int32($0), name: "test", bytesIn: Double($0), bytesOut: 0) }
assert(ProcessTraffic.top(many, direction: .down).map(\.id) == [10, 9, 8, 7, 6])
print("Process traffic parser and ranking tests passed")

if CommandLine.arguments.contains("--live") {
    let store = ProcessTrafficStore()
    var updates = 0
    var subscription: AnyCancellable?
    subscription = store.$isLoading.dropFirst().sink { loading in
        guard !loading else { return }
        DispatchQueue.main.async {
            assert(store.error == nil, store.error ?? "")
            updates += 1
            if updates == 3 {
                store.stop()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    assert(updates == 3, "Sampling continued after stop")
                    print("Live sampling: three updates received; stopped successfully")
                    exit(0)
                }
            }
        }
    }
    store.start()
    DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
        store.stop()
        print("FAIL: live sampling did not finish")
        exit(1)
    }
    RunLoop.main.run()
    withExtendedLifetime(subscription) {}
}
