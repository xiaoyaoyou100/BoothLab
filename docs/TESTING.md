# 测试与验收

测试结果来自冻结提交 205faeaa60e07673e7fd04662f344f4e751a19e8 的归档。本轮公共材料复核沿用该结果。已验证的工具和构建目标见[运行指南](GETTING_STARTED.md)。

| 验证入口 | 归档结果 | 验证边界 |
| --- | --- | --- |
| 默认 Hypium | 16 个结果类，233/233 PASS，failure/error/ignore 各 0 | Hvigor test，从 src/test/List.test.ets 汇集。 |
| 独立 Viewport 数学 | 12/12 PASS | 独立宿主 runner 用 SDK TypeScript 转译并断言。覆盖正反坐标、缩放与平移限幅、焦点、适配、异常输入。 |
| CompileArkTS / assembleHap | PASS / PASS | debug 离线构建，PlanLibrary 重复组件 ID 警告保留。 |
| INT-01 / INT-02 / INT-03 | PASS / PASS / PASS | API 17 Phone 上实测编辑、三案进程重启恢复、碰撞与入口。 |
| UX03 最终矩阵 | 10 PASS / 1 PARTIAL / 1 NOT RUN | 设备专项与负责人复核，LIMITED_ACCEPTED。 |

默认 Hypium 和独立数学入口分别统计。entry/src/ohosTest 是另一个设备测试目标，设备验收采用归档的实际界面操作及数据核对。

~~~powershell
& $hvigor test --mode module -p product=default -p module=entry@default -p buildMode=debug --no-daemon
~~~

$hvigor 为[运行指南](GETTING_STARTED.md)中配置的 Windows 启动器变量。独立数学用例见 [EditorViewTransform.test.ets](../entry/src/test/EditorViewTransform.test.ets)，其 UX03-01 归档 runner 为 VIEWPORT-RUNNER.cjs。默认入口见 [List.test.ets](../entry/src/test/List.test.ets)。

## 双成员的 SRS 用例

郑鑫越负责 A-T01～06，贾云翔负责 B-T01～06。SRS 中的 12 个编号是验收场景，源码使用下表中的 Hypium it 名称。下面 12 个 SRS 规划用例对应 16 个实际执行的测试函数。部分场景由多个函数共同覆盖，源码中另有回归用例。以下 PASS 出自 UX03-01 的 HYPIUM-TEST-RESULT-RAW.txt，行号便于在课程验收归档中复核。

| 规划 ID / 成员 | 需求 / 类别 | 实际用例 | 输入与关键断言 | 结果与原始日志行 | 与 SRS 示例及覆盖的差异 |
| --- | --- | --- | --- | --- | --- |
| A-T01 郑鑫越 | FR-03 · 正常 | [addObjectUsesCatalogCentreAndDeterministicUniqueIds](../entry/src/test/Editor.test.ets#L101) | 标准展位含默认桌，添加座椅 (100,100) 和绿植 (500,100)。返回 obj-2、obj-3，座椅中心及占地正确，3 件 ID 互异。 | PASS · 34 | SRS 示例为空展位添加展示桌；源码采用默认桌和两种物件。 |
| A-T02 郑鑫越 | FR-05/08 · 正常 | [moveUndoRedoRestoresCentreAndKeepsId](../entry/src/test/History.test.ets#L117) | obj-1 从 (300,200) 移至 (400,200)。Undo 回 (300,200)，Redo 回 (400,200)，保留 obj-1。 | PASS · 239 | 与 SRS 坐标一致。 |
| A-T03 郑鑫越 | FR-06 · 边界 | [fourClockwiseRotationsSwapFootprintAndReturnToStart](../entry/src/test/Editor.test.ets#L154) | 标准展位展示桌 120×60，连续顺时针旋转四次。90/270° 占地 60×120，180/0° 为 120×60，中心不变。 | PASS · 38 | 与 SRS 几何示例一致。 |
| A-T04 郑鑫越 | FR-10 · 边界 | [edgeContactAndSmallGapAreNotOverlaps](../entry/src/test/Layout.test.ets#L112)、[overlappingFootprintsProduceOnePairIssue](../entry/src/test/Layout.test.ets#L96) | 同向展示桌中心 (240,200)/(360,200) 接触，另以 (300,200)/(350,200) 相交。接触和间隙为零条 OVERLAP；面积相交一条告警含两实例 ID。 | PASS · 292、290 | 两个源码用例合并映射。 |
| A-T05 郑鑫越 | FR-05/09 · 异常 | [moveObjectCommitsValidCentreAndRejectsOutOfBounds](../entry/src/test/Editor.test.ets#L134) | 先将展示桌移至 (400,200)，再尝试 (590,200)。OUT_OF_BOUNDS，已提交点仍为 (400,200)。 | PASS · 36 | SRS 示例 x=595；测试等价越界分支用 x=590。 |
| A-T06 郑鑫越 | FR-07/08 · 异常 | [invalidMoveRotateRemoveAndAddRecordNoHistory](../entry/src/test/History.test.ets#L227) | 对 missing ID 删除、移动、旋转，并尝试非法新增。删除返回 NOT_FOUND，物件数仍为 1，无撤销或重做。 | PASS · 251 | 一个组合用例覆盖多种非法操作。 |
| B-T01 贾云翔 | FR-01/12 · 正常 | [createPlanTrimsNameAndStartsWithEmptyObjectsAndPersists](../entry/src/test/PlanRepository.test.ets#L215) | TestSnapshotStorage，名称“  春季展位  ”，standard。去除首尾空白，写入 1 次，存档 ID 与新建 ID 相同，列表中有 1 份，状态 Saved。 | PASS · 74 | SRS 示例名为“科技节 A 区”。 |
| B-T02 贾云翔 | FR-13/14/17 · 正常 | [saveThreePlansAndReloadAllWithIsolatedReads](../entry/src/test/Persistence.test.ets#L448)、[moveAndRotationPersistAcrossRestart](../entry/src/test/Persistence.test.ets#L474) | FakePreferencesIO 建三案；另一测试保存座椅 (300,200,90°) 与接待台 (400,250,270°)。重开保留三案与名称或模板，另一测试核对物件位置与旋转。 | PASS · 143、145 | 两项宿主用例分别验证三案和物件；同时验证三案不同物件走 INT-02。 |
| B-T03 贾云翔 | FR-13/14 · 正常 | [threePlansHaveUniqueIdsAndFullyIndependentListObjects](../entry/src/test/PlanRepository.test.ets#L283)、[savePlanPersistsRealObjectsAndListShowsThemWithIsolation](../entry/src/test/PlanRepository.test.ets#L311) | 三案，修改列表返回的首案名称和物件；另以接待台和座椅保存方案后修改返回对象。列表克隆隔离，重新读取保留原名、物件数或中心；保存位置和角度正确。 | PASS · 82、84 | Mock 用例覆盖克隆及单案写入；跨案写入再读的组合证据为 UX03-07 与 INT-02。 |
| B-T04 贾云翔 | FR-12/16 · 边界 | [createPlanEnforcesTrimmedNameBoundariesAndUnknownTemplate](../entry/src/test/PlanRepository.test.ets#L255) | 全空白、30 位数字和追加第 31 位。30 字符通过；31 字符与全空白返回 INVALID_ARGUMENT。 | PASS · 78 | 也包含未知模板负例。 |
| B-T05 贾云翔 | FR-01/12/16 · 异常 | [createPlanRejectsUnknownTemplateWithoutMutation](../entry/src/test/PlanRepository.test.ets#L272) | 有效名称和 island 模板。INVALID_ARGUMENT，仓库仍为空，写入次数为 0。 | PASS · 80 | 宿主 Mock。 |
| B-T06 贾云翔 | FR-14/16/NFR-03/04/09 · 异常 | [bothCorruptFailsWithoutOverwriteAndBlocksMutations](../entry/src/test/Persistence.test.ets#L647)、[primaryFlushFailureDiscardsCachedPutAndNextWriteDoesNotLeak](../entry/src/test/Persistence.test.ets#L543) | 主快照 {broken 与备份 []；另一用例令主 flush 失败。CORRUPTED_DATA 且原值不变；PERSISTENCE_ERROR、SaveError 且旧方案保持，之后可重试。 | PASS · 159、151 | 破坏性真机用例仍为 UX03-09 NOT RUN。 |

## 成员用例与设备场景对照

下表按业务路径关联同一 SRS 用例的宿主断言与设备场景。宿主输入、设备操作和异常模拟分别以各自记录为准。

| 用例 / 负责成员 | 宿主测试函数 | 覆盖目标 | 关联设备场景 | 证据性质 | 结果与限制 |
| --- | --- | --- | --- | --- | --- |
| A-T01 郑鑫越 | [addObjectUsesCatalogCentreAndDeterministicUniqueIds](../entry/src/test/Editor.test.ets#L101) | 目录添加及实例 ID | UX03-02、UX03-03、INT-01 | 宿主断言、设备验收 | 宿主 PASS。设备 PASS。宿主另核对确定性 ID。 |
| A-T02 郑鑫越 | [moveUndoRedoRestoresCentreAndKeepsId](../entry/src/test/History.test.ets#L117) | 拖动后恢复中心及 ID | UX03-03、UX03-05、INT-01 | 宿主断言、设备验收 | 宿主 PASS。设备 PASS。宿主断言指定坐标和实例 ID。 |
| A-T03 郑鑫越 | [fourClockwiseRotationsSwapFootprintAndReturnToStart](../entry/src/test/Editor.test.ets#L154) | 四次旋转恢复占地 | UX03-03、INT-01 | 宿主断言、设备验收 | 宿主 PASS。设备 PASS。宿主断言中心和占地。 |
| A-T04 郑鑫越 | [edgeContactAndSmallGapAreNotOverlaps](../entry/src/test/Layout.test.ets#L112)、[overlappingFootprintsProduceOnePairIssue](../entry/src/test/Layout.test.ets#L96) | 接触、间隙和面积相交 | UX03-04、INT-03 | 宿主断言、设备验收 | 宿主 PASS。设备 PASS。宿主分两项断言接触与相交。 |
| A-T05 郑鑫越 | [moveObjectCommitsValidCentreAndRejectsOutOfBounds](../entry/src/test/Editor.test.ets#L134) | 越界拒绝且保留已提交位置 | UX03-04、INT-03 | 宿主断言、设备验收 | 宿主 PASS。设备 PASS。宿主用 x=590 验证越界。 |
| A-T06 郑鑫越 | [invalidMoveRotateRemoveAndAddRecordNoHistory](../entry/src/test/History.test.ets#L227) | 非法编辑不产生历史 | UX03-03、UX03-05、INT-01 正常删除与历史 | 宿主断言、设备旁证 | 宿主 PASS。设备关联场景 PASS。失效 ID 与非法操作组合由宿主覆盖。 |
| B-T01 贾云翔 | [createPlanTrimsNameAndStartsWithEmptyObjectsAndPersists](../entry/src/test/PlanRepository.test.ets#L215) | 建案、名称去空白和首次写入 | UX03-01、UX03-07、INT-01 | 宿主 Mock、设备验收 | 宿主 PASS。设备 PASS。宿主断言空物件列表与写入次数。 |
| B-T02 贾云翔 | [saveThreePlansAndReloadAllWithIsolatedReads](../entry/src/test/Persistence.test.ets#L448)、[moveAndRotationPersistAcrossRestart](../entry/src/test/Persistence.test.ets#L474) | 三案持久化、重启与续编 | UX03-07、UX03-08、INT-02 | 宿主 Mock、设备验收 | 宿主 PASS。设备 PASS。宿主分别核对三案读取和物件状态。 |
| B-T03 贾云翔 | [threePlansHaveUniqueIdsAndFullyIndependentListObjects](../entry/src/test/PlanRepository.test.ets#L283)、[savePlanPersistsRealObjectsAndListShowsThemWithIsolation](../entry/src/test/PlanRepository.test.ets#L311) | 保存、跨案数据和返回副本隔离 | UX03-07、INT-02 | 宿主 Mock、设备验收 | 宿主 PASS。设备跨案流程 PASS。返回副本隔离由宿主断言。 |
| B-T04 贾云翔 | [createPlanEnforcesTrimmedNameBoundariesAndUnknownTemplate](../entry/src/test/PlanRepository.test.ets#L255) | 方案名称边界 | UX03-01、UX03-07 | 宿主 Mock、设备验收 | 宿主 PASS。设备名称校验 PASS。测试中的未知模板分支由宿主覆盖。 |
| B-T05 贾云翔 | [createPlanRejectsUnknownTemplateWithoutMutation](../entry/src/test/PlanRepository.test.ets#L272) | 拒绝未知模板且不写入 | UX03-01 两种合法模板 | 宿主 Mock、设备旁证 | 宿主 PASS。合法模板设备 PASS。未知模板拒绝为宿主 Mock。 |
| B-T06 贾云翔 | [bothCorruptFailsWithoutOverwriteAndBlocksMutations](../entry/src/test/Persistence.test.ets#L647)、[primaryFlushFailureDiscardsCachedPutAndNextWriteDoesNotLeak](../entry/src/test/Persistence.test.ets#L543) | 主备损坏与 flush 失败 | UX03-08、INT-02 正常重启 | 宿主 Mock、设备旁证 | 宿主 PASS。正常恢复设备 PASS，作为旁证。破坏性设备恢复 UX03-09 NOT RUN。 |

## 设备集成

| 用例 | 操作与核对 | 结果 / 归档索引 |
| --- | --- | --- |
| INT-01 | 标准型先放至少六件，再拖动、旋转、删除并撤销与重做。核对计数、中心及角度。 | PASS · INT-EXECUTION-LEDGER.csv，INT01-A 系列。 |
| INT-02 | 三份独立方案保存后受控结束进程并重启，逐份核对 ID、名称、模板、位置、角度、数量，再继续编辑。 | PASS · 同一台账，INT02 系列，RESTART 及逐案对照。 |
| INT-03 | 制造正面积重叠和入口占用，再尝试越界并修正。核对告警出现和消除，越界未提交。 | PASS · 同一台账，INT03-B 系列。 |

API 17 Phone 设备上的小屏专项采用 1260 × 2720 px、3.25 px/vp 的竖屏标准字体环境，宽约 387.69 vp。核心设备用例 UX03-01～08 及小屏／输入法 UX03-11 通过。UX03-09 为 NOT RUN，UX03-10 为 PARTIAL。

UX03-12 经项目负责人复核通过，归档记载两个成员个人签认未另行提供。设备破坏性故障注入和重装未执行。真实多指并发和大字体、Tablet／2in1 仍待单独验证。[图片与操作脚本](DEMO.md) · [已知限制](LIMITATIONS.md)
