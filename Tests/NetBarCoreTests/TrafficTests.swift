import Foundation
import Testing
@testable import NetBarCore

@Suite("流量解析与显示")
struct TrafficTests {
    @Test("内核 PID 0 不应导致整帧采样失败", arguments: [0.0, 128.0])
    func kernelProcess(download: Double) throws {
        // 来自故障机器的最小样本，保留内核、普通进程和第二帧新增进程。
        let rows = try NetTopParser.parse("""
        ,bytes_in,bytes_out,
        kernel_task.0,2904,2356,
        launchd.1,0,0,
        ClashX Pro.717,283688469,282509991,
        ,bytes_in,bytes_out,
        kernel_task.0,\(download),0,
        launchd.1,0,0,
        EasyMonitor.242,1395,986,
        ClashX Pro.717,406723,402913,
        """)
        #expect(rows == [
            ProcessTraffic(pid: 0, name: "kernel_task", download: download, upload: 0),
            ProcessTraffic(pid: 1, name: "launchd", download: 0, upload: 0),
            ProcessTraffic(pid: 242, name: "EasyMonitor", download: 1395, upload: 986),
            ProcessTraffic(pid: 717, name: "ClashX Pro", download: 406723, upload: 402913)
        ])
    }

    @Test("nettop 缺少名称时仍按 PID 展示该进程")
    func unnamedProcess() throws {
        let rows = try NetTopParser.parse("""
        ,bytes_in,bytes_out,
        .85300,0,20037,
        ,bytes_in,bytes_out,
        .85300,0,128,
        """)
        #expect(rows == [ProcessTraffic(pid: 85300, name: "未命名进程", download: 0, upload: 128)])
    }

    @Test("跳过累计值、保留空闲进程、按列名解析")
    func deltaSample() throws {
        let rows = try NetTopParser.parse("""
        ,bytes_out,bytes_in,
        Browser.10,9000000,8000000,
        ,bytes_out,bytes_in,
        Browser.10,2500,1250000,
        com.example.helper.11,0,0,
        """)
        #expect(rows == [
            ProcessTraffic(pid: 10, name: "Browser", download: 1_250_000, upload: 2_500),
            ProcessTraffic(pid: 11, name: "com.example.helper", download: 0, upload: 0)
        ])
    }

    @Test("进程名称支持空格、点和 CSV 引号")
    func processNames() throws {
        let rows = try NetTopParser.parse("""
        ,bytes_in,bytes_out,
        ,bytes_in,bytes_out,
        "My, \"\"Browser\"\".Helper.42",12,34,
        """)
        #expect(rows.first?.name == "My, \"Browser\".Helper")
        #expect(rows.first?.pid == 42)
    }

    @Test("坏样本不能变为零速率", arguments: [
        "", "permission denied", ",bytes_in,bytes_out,\nApp.1,100,200,",
        ",bytes_in,bytes_out,\n,bytes_in,bytes_out,\nApp.1,broken,20,",
        ",bytes_in,bytes_out,\n,bytes_in,bytes_out,\nApp.1,nan,20,",
        ",bytes_in,bytes_out,\n,bytes_in,bytes_out,\nApp.1,-1,20,",
        ",bytes_in,bytes_out,\n,bytes_in,bytes_out,\nApp.-1,1,2,",
        ",bytes_in,bytes_out,\n,bytes_in,bytes_out,\nkernel_task.0,1,2,\nkernel_task.0,3,4,",
        ",bytes_in,bytes_out,\n,bytes_in,bytes_out,\nApp.1,1,2,\nApp.1,3,4,"
    ])
    func invalidSamples(output: String) {
        #expect(throws: SamplingError.self) { try NetTopParser.parse(output) }
    }

    @Test("合法空列表")
    func emptySample() throws {
        #expect(try NetTopParser.parse(",bytes_in,bytes_out,\n,bytes_in,bytes_out,\n").isEmpty)
    }

    @Test("十进制单位与两位小数")
    func units() {
        #expect(TrafficRate.string(0) == "0.00 KB/s")
        #expect(TrafficRate.string(125_000) == "125.00 KB/s")
        #expect(TrafficRate.string(999_990) == "999.99 KB/s")
        #expect(TrafficRate.string(1_000_000) == "1.00 MB/s")
        #expect(TrafficRate.string(2_500_000) == "2.50 MB/s")
    }

    @Test("下载、上传升降序及稳定的相同速率排序")
    func sorting() {
        let rows = [
            ProcessTraffic(pid: 3, name: "C", download: 10, upload: 90),
            ProcessTraffic(pid: 2, name: "B", download: 20, upload: 10),
            ProcessTraffic(pid: 1, name: "A", download: 10, upload: 50)
        ]
        #expect(TrafficSort.download.sorted(rows).map(\.pid) == [2, 1, 3])
        #expect(TrafficSort.download.sorted(rows, ascending: true).map(\.pid) == [1, 3, 2])
        #expect(TrafficSort.upload.sorted(rows).map(\.pid) == [3, 1, 2])
        #expect(TrafficSort.upload.sorted(rows, ascending: true).map(\.pid) == [2, 1, 3])
    }
}
