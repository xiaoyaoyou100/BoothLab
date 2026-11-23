# 软件需求追踪

以[软件需求说明书](../软件需求说明书/软件需求说明书.docx)的 FR、NFR 和测试 ID 为准。A 为郑鑫越，B 为贾云翔。下列状态注明证据层级，UX03 为正式矩阵编号。Viewport、LOD 和 IME 沿用 UX 编号。测试函数、归档位置及适用边界见[测试指南](TESTING.md)和[已知限制](LIMITATIONS.md)。

| ID / 职责 | SRS 要点 | 实现 | 测试与证据 | 结果 | 范围 |
| --- | --- | --- | --- | --- | --- |
| FR-01 B | 模板选择 | [BoothTemplates](../entry/src/main/ets/catalog/BoothTemplates.ets) | B-T01/05，UX03-01 | PASS | 两种 600×400 cm 底图，错误模板见 Mock。 |
| FR-02 B | 物件目录 | [ObjectCatalogData](../entry/src/main/ets/catalog/ObjectCatalogData.ets)、[ObjectCatalogPicker](../entry/src/main/ets/components/catalog/ObjectCatalogPicker.ets)、[ObjectVisuals](../entry/src/main/ets/components/catalog/ObjectVisuals.ets) | UX03-02/10，CatalogTest | PASS（目录）；PARTIAL（视觉专项） | rollup 在界面显示“立式海报架”；展品台低档和座椅名称见限制。 |
| FR-03 A+B | 添加物件 | [EditorWorkspace](../entry/src/main/ets/components/editor/EditorWorkspace.ets)、[EditorController](../entry/src/main/ets/engine/EditorController.ets) | A-T01，UX03-02/03，INT-01 | PASS | 实例唯一并在合法位置添加。 |
| FR-04 A | 选中反馈 | [EditorWorkspace](../entry/src/main/ets/components/editor/EditorWorkspace.ets)、[EditorController](../entry/src/main/ets/engine/EditorController.ets) | UX03-03/06 | PASS | 点选和空白取消；文字显示边界见 UX03-10。 |
| FR-05 A | 拖动调整 | [EditorController](../entry/src/main/ets/engine/EditorController.ets)、[HistoryManager](../entry/src/main/ets/engine/HistoryManager.ets) | A-T02/05，UX03-03，INT-01 | PASS | 拖动提交，历史单条；真实多指并发未测。 |
| FR-06 A | 物件旋转 | [EditorController](../entry/src/main/ets/engine/EditorController.ets)、[GeometryEngine](../entry/src/main/ets/engine/GeometryEngine.ets) | A-T03，UX03-03/04，INT-01 | PASS | 90° 递进，越界旋转拒绝。 |
| FR-07 A | 删除与撤销 | [EditorController](../entry/src/main/ets/engine/EditorController.ets)、[HistoryManager](../entry/src/main/ets/engine/HistoryManager.ets) | A-T06，UX03-03/05，INT-01 | PASS | 删除仅影响目标，Undo 恢复，Redo 再删。 |
| FR-08 A | 撤销与重做 | [HistoryManager](../entry/src/main/ets/engine/HistoryManager.ets)、[EditorController](../entry/src/main/ets/engine/EditorController.ets) | A-T02/06，UX03-05 | PASS | 容量 50 有宿主证据。 |
| FR-09 A | 边界检测 | [GeometryEngine](../entry/src/main/ets/engine/GeometryEngine.ets)、[LayoutValidator](../entry/src/main/ets/engine/LayoutValidator.ets) | A-T05，UX03-04，INT-03 | PASS | 贴边可用且越界拒绝。 |
| FR-10 A | 重叠检测 | [LayoutValidator](../entry/src/main/ets/engine/LayoutValidator.ets)、[GeometryEngine](../entry/src/main/ets/engine/GeometryEngine.ets) | A-T04，UX03-04，INT-03 | PASS | 接触不报，正面积重叠可定位。 |
| FR-11 A+B | 入口保护 | [BoothTemplates](../entry/src/main/ets/catalog/BoothTemplates.ets)、[LayoutValidator](../entry/src/main/ets/engine/LayoutValidator.ets) | UX03-04，INT-03 | PASS | 入口预留区是教学模拟提醒。 |
| FR-12 B | 新建/命名方案 | [PlanLibrary](../entry/src/main/ets/components/plan/PlanLibrary.ets)、[PlanRepository](../entry/src/main/ets/repository/PlanRepository.ets) | B-T01/04/05，UX03-07/11 | PASS | 名称去首尾空白后 1–30 字符。 |
| FR-13 B | 方案列表预览 | [PlanLibrary](../entry/src/main/ets/components/plan/PlanLibrary.ets)、[PlanThumbnail](../entry/src/main/ets/components/plan/PlanThumbnail.ets) | B-T02/03，UX03-07，INT-02 | PASS | 独立缩略图和方案。 |
| FR-14 B | 保存与加载 | [Index](../entry/src/main/ets/pages/Index.ets)、[SaveCoordinator](../entry/src/main/ets/application/SaveCoordinator.ets)、[PlanRepository](../entry/src/main/ets/repository/PlanRepository.ets)、[PreferencesStore](../entry/src/main/ets/storage/PreferencesStore.ets) | B-T02/03/06，UX03-07/08，INT-02 | PASS（手动和离页）；PARTIAL（编辑后自动保存条款） | 离页保存已测；源码提交编辑后标记 Dirty，当前无编辑后定时防抖保存。 |
| FR-15 B | 删除方案 | [PlanLibrary](../entry/src/main/ets/components/plan/PlanLibrary.ets)、[PlanRepository](../entry/src/main/ets/repository/PlanRepository.ets) | UX03-07，PlanRepositoryTest | PASS | 取消和确认删除用独立测试副本。 |
| FR-16 B | 异常恢复 | [PlanRepository](../entry/src/main/ets/repository/PlanRepository.ets)、[PlanSerializer](../entry/src/main/ets/repository/PlanSerializer.ets)、[PlanValidator](../entry/src/main/ets/repository/PlanValidator.ets)、[PreferencesStore](../entry/src/main/ets/storage/PreferencesStore.ets) | B-T04/05/06，UX03-09 | PARTIAL | 名称、模板和 Mock 异常有证据，设备故障注入与重装 NOT RUN。 |
| FR-17 B+A | 生命周期恢复 | [Index](../entry/src/main/ets/pages/Index.ets)、[PlanRepository](../entry/src/main/ets/repository/PlanRepository.ets)、[PreferencesStore](../entry/src/main/ets/storage/PreferencesStore.ets) | B-T02，UX03-08，INT-02 | PASS | 三案在实际进程重启后恢复并续编；破坏性范围另见 UX03-09。 |
| FR-18 A+B | 状态与视觉反馈 | [EditorWorkspace](../entry/src/main/ets/components/editor/EditorWorkspace.ets)、[Index](../entry/src/main/ets/pages/Index.ets)、[SaveCoordinator](../entry/src/main/ets/application/SaveCoordinator.ets) | UX03-03/08/10/11，B-T06 | PASS（核心）；PARTIAL（视觉） | 区分选择、错误及保存状态，视觉名称边界保留。 |
| NFR-01 A+B | 完成有效编辑后标记 Dirty，用户主动保存时必须等待写入成功再显示“已保存” | [Index](../entry/src/main/ets/pages/Index.ets)、[SaveCoordinator](../entry/src/main/ets/application/SaveCoordinator.ets) | UX03-08，SaveCoordinator 宿主套件 | PASS | 有效编辑置 Dirty，保存回执确认后显示 Saved。 |
| NFR-02 A+B | 自动保存建议 600 ms 防抖，正在拖动时不得逐帧写入，离开编辑页时补做一次保存确认 | [Index](../entry/src/main/ets/pages/Index.ets)、[SaveCoordinator](../entry/src/main/ets/application/SaveCoordinator.ets)、[EditorController](../entry/src/main/ets/engine/EditorController.ets) | UX03-03/08，History 与 SaveCoordinator 宿主套件 | PARTIAL | 拖动预览不逐帧写入，返回前补保存；600 ms 为 SRS 建议值，当前没有定时触发路径。 |
| NFR-03 B | 存储项包含 schemaVersion，读取后进行必需字段和类型校验 | [BoothModels](../entry/src/main/ets/model/BoothModels.ets)、[PlanSerializer](../entry/src/main/ets/repository/PlanSerializer.ets)、[PlanValidator](../entry/src/main/ets/repository/PlanValidator.ets) | B-T06，PlanRepositoryTest | PASS（宿主） | schemaVersion 与字段校验；未来版本拒绝。 |
| NFR-04 B | 对损坏主快照提供最近有效快照的恢复尝试，未能恢复时提示用户，不崩溃，不覆盖原值 | [PlanRepository](../entry/src/main/ets/repository/PlanRepository.ets)、[PreferencesStore](../entry/src/main/ets/storage/PreferencesStore.ets) | B-T06，Persistence 宿主套件，UX03-09 | PASS（宿主）；NOT RUN（设备破坏性） | 主坏回退有效备份；无法恢复时保护原值。 |
| NFR-05 A+B | 关进程后只要求恢复最后一次成功写入的方案，拖动中预览和撤销栈不要求恢复 | [Index](../entry/src/main/ets/pages/Index.ets)、[PlanRepository](../entry/src/main/ets/repository/PlanRepository.ets)、[PlanSerializer](../entry/src/main/ets/repository/PlanSerializer.ets) | UX03-08，INT-02 | PASS | 恢复成功落盘数据；预览、撤销和视口不属于持久化状态。 |
| NFR-06 B | 存档数据只保存在应用沙箱内，无需联网和注册 | [PreferencesStore](../entry/src/main/ets/storage/PreferencesStore.ets) | 源码配置与 API 17 保存恢复 | PASS（源码与设备流程） | 沙箱本地，核心流程无需联网或账户。 |
| NFR-07 B+A | 同一编辑器同一时刻最多执行一个在途写入，避免旧快照覆盖新快照 | [PlanRepository](../entry/src/main/ets/repository/PlanRepository.ets)、[SaveCoordinator](../entry/src/main/ets/application/SaveCoordinator.ets) | UX03-08，deferredWritesStaySerializedWithMaxOneInflight | PASS（宿主串行断言） | 范围为同实例队列。 |
| NFR-08 A | 在选定的 HarmonyOS 手机模拟器/真机上，单方案 30 个物件连续编辑 20 次无崩溃或明显坐标漂移 | [EditorWorkspace](../entry/src/main/ets/components/editor/EditorWorkspace.ets)、[EditorController](../entry/src/main/ets/engine/EditorController.ets) | G4 30 物件 / 20 次编辑压力复核 | PASS（历史 G4）；NOT RUN（固定 UX03 同规模） | 历史 G4 为 30 次添加与 20 次编辑，4 次拖动核对误差≤0.4 cm。 |
| NFR-09 A+B | 所有保存操作具备保存中、已保存或失败的明确状态，不会在失败后显示成功 | [Index](../entry/src/main/ets/pages/Index.ets)、[SaveCoordinator](../entry/src/main/ets/application/SaveCoordinator.ets)、[PlanRepository](../entry/src/main/ets/repository/PlanRepository.ets) | UX03-08，B-T06 | PASS（正常设备 + 宿主失败） | 实际设备注入失败未执行。 |
| NFR-10 A+B | 中文正文无遮挡、主要按钮可点，390 vp 设计基准下竖屏编辑可用 | [EditorWorkspace](../entry/src/main/ets/components/editor/EditorWorkspace.ets)、[PlanLibrary](../entry/src/main/ets/components/plan/PlanLibrary.ets) | UX03-10/11 | PASS（约 388 vp 标准操作）；PARTIAL（视觉） | 工具栏模板信息 S3，座椅画布名称专项 PARTIAL。 |
| NFR-11 A+B | 应用首版以 Phone 为主要验收设备，Tablet/2in1 已在配置中勾选，但须单独验证适配后才能宣称支持良好 | [module](../entry/src/main/module.json5) | UX03-11 | PASS（Phone）；NOT RUN（Tablet／2in1） | 配置声明三类设备，验收为 Phone 标准档。 |
| NFR-12 A+B | 本项目的“入口保护”仅作为教学模拟提醒，不输出消防安全或实际施工合规结论 | [LayoutValidator](../entry/src/main/ets/engine/LayoutValidator.ets)、[EditorWorkspace](../entry/src/main/ets/components/editor/EditorWorkspace.ets) | UX03-04/12，INT-03 | PASS | 入口说明限于教学布局。 |
| NFR-13 A+B | 工程包名固定 com.example.boothlab，Stage 模型及 entry 模块保持一致 | [app](../AppScope/app.json5)、[build-profile](../build-profile.json5)、[module](../entry/src/main/module.json5) | 冻结配置和 CompileArkTS/assembleHap | PASS | com.example.boothlab、Stage、entry。 |
| INT-01 A+B | 新建标准展位→添加≥6 个物件→拖动、旋转、删除→Undo/Redo→检查布局。 | [EditorWorkspace](../entry/src/main/ets/components/editor/EditorWorkspace.ets)、[EditorController](../entry/src/main/ets/engine/EditorController.ets) | UX03-12，INT01-A | PASS | 标准模板至少六件及编辑回退链。 |
| INT-02 A+B | 创建 3 份命名方案→分别保存→结束应用进程→重启→重新打开。 | [Index](../entry/src/main/ets/pages/Index.ets)、[PlanRepository](../entry/src/main/ets/repository/PlanRepository.ets)、[PreferencesStore](../entry/src/main/ets/storage/PreferencesStore.ets) | UX03-12，INT02 | PASS | 受控停止重启，三案逐份重开与续编。 |
| INT-03 A+B | 故意重叠两物件、占用入口、拖动越界，再修正。 | [EditorWorkspace](../entry/src/main/ets/components/editor/EditorWorkspace.ets)、[LayoutValidator](../entry/src/main/ets/engine/LayoutValidator.ets) | UX03-12，INT03-B | PASS | 重叠、入口、越界及修正。 |

## 成员用例对应关系

每项测试的实际函数、输入、断言及归档结果见[双成员用例](TESTING.md#双成员的-srs-用例)。

| 规划编号 | 需求 | 类别 | 归档结果与边界 |
| --- | --- | --- | --- |
| A-T01 郑鑫越 | FR-03 | 正常 | PASS（宿主）。SRS 示例为空展位添加展示桌；源码采用默认桌和两种物件。 |
| A-T02 郑鑫越 | FR-05/08 | 正常 | PASS（宿主）。与 SRS 坐标一致。 |
| A-T03 郑鑫越 | FR-06 | 边界 | PASS（宿主）。与 SRS 几何示例一致。 |
| A-T04 郑鑫越 | FR-10 | 边界 | PASS（宿主）。两个源码用例合并映射。 |
| A-T05 郑鑫越 | FR-05/09 | 异常 | PASS（宿主）。SRS 示例 x=595；测试等价越界分支用 x=590。 |
| A-T06 郑鑫越 | FR-07/08 | 异常 | PASS（宿主）。一个组合用例覆盖多种非法操作。 |
| B-T01 贾云翔 | FR-01/12 | 正常 | PASS（宿主）。SRS 示例名为“科技节 A 区”。 |
| B-T02 贾云翔 | FR-13/14/17 | 正常 | PASS（宿主）。单位用例分别证明三案和物件；同时验证三案不同物件走 INT-02。 |
| B-T03 贾云翔 | FR-13/14 | 正常 | PASS（宿主）。Mock 用例覆盖克隆及单案写入；跨案写入再读的组合证据为 UX03-07 与 INT-02。 |
| B-T04 贾云翔 | FR-12/16 | 边界 | PASS（宿主）。也包含未知模板负例。 |
| B-T05 贾云翔 | FR-01/12/16 | 异常 | PASS（宿主）。宿主 Mock。 |
| B-T06 贾云翔 | FR-14/16/NFR-03/04/09 | 异常 | PASS（宿主）。破坏性真机用例仍为 UX03-09 NOT RUN。 |
