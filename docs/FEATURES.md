# 功能说明

BoothLab 是面向展位布局练习的 HarmonyOS 应用。用户可以从模板开始，在画布中摆放设施、检查布局问题，并将多份方案保存在本地。以下状态来自 UX03 最终验收矩阵；验收范围及例外见[已知限制](LIMITATIONS.md)。

| 使用场景与操作 | 需求和实现 | 验证范围 |
| --- | --- | --- |
| 新建方案：输入名称，选择标准型或转角型。两种模板均为 600 × 400 cm，围挡和开放边不同。 | FR-01、FR-12；[模板数据](../entry/src/main/ets/catalog/BoothTemplates.ets)、[方案库](../entry/src/main/ets/components/plan/PlanLibrary.ets) | UX03-01、07：设备 PASS；空名称和超过 30 字符的名称被拒绝。宿主测试覆盖[两种内置模板建案](../entry/src/test/PlanRepository.test.ets#L240)。 |
| 添加设施：浏览六个分类，从十类物件中选择并添加；同类物件可各自编辑。目录中的“立式海报架”对应需求中的易拉宝（rollup）。 | FR-02、FR-03；[物件目录](../entry/src/main/ets/catalog/ObjectCatalogData.ets)、[目录选择器](../entry/src/main/ets/components/catalog/ObjectCatalogPicker.ets) | UX03-02、03：十类均核对并添加，设备 PASS。宿主测试核对[十类物件目录数据](../entry/src/test/Catalog.test.ets#L165)。 |
| 编辑布局：点击物件查看选中信息，拖动位置，以 90° 为步长旋转，或删除物件；点击空白取消选择。 | FR-04～07、FR-18；[编辑界面](../entry/src/main/ets/components/editor/EditorWorkspace.ets)、[编辑控制器](../entry/src/main/ets/engine/EditorController.ets) | UX03-03：设备 PASS；同类实例独立。宿主测试覆盖[删除及其撤销重做](../entry/src/test/History.test.ets#L148)，以及[非法编辑无历史](../entry/src/test/History.test.ets#L227)。 |
| 撤销与重做：对添加、移动、旋转和删除进行撤销或重做；撤销后执行新编辑会清空重做记录。 | FR-07、FR-08；[历史管理](../entry/src/main/ets/engine/HistoryManager.ets) | UX03-05：四类操作设备 PASS；宿主测试覆盖[第 51 步淘汰最早记录](../entry/src/test/History.test.ets#L193)及[新编辑清除重做分支](../entry/src/test/History.test.ets#L210)。 |
| 检查布局：越界操作被拒绝；物件面积重叠或占用入口时显示可定位的问题，调整后可清除。贴边及仅接触不视为越界或重叠。入口提示仅供教学模拟，不代表消防或施工合规结论。 | FR-09～11；[布局校验](../entry/src/main/ets/engine/LayoutValidator.ets)、[几何计算](../entry/src/main/ets/engine/GeometryEngine.ets) | UX03-04：设备 PASS，覆盖贴边、接触、重叠、入口和越界。宿主 A-T04 验证[面积相交](../entry/src/test/Layout.test.ets#L96)与[边缘接触](../entry/src/test/Layout.test.ets#L112)，A-T05 验证[越界不提交](../entry/src/test/Editor.test.ets#L134)。 |
| 查看画布：适配全图、调整倍率、聚焦及平移，并可在缩放后继续编辑。视图操作不写入业务撤销历史。 | UX 扩展，关联 FR-04、05、08、09、14；[视口变换](../entry/src/main/ets/components/editor/EditorViewTransform.ets) | UX03-06：设备 PASS，覆盖全图、至 250% 缩放、160% 聚焦、平移和重开。另有[独立 Viewport 数学用例](../entry/src/test/EditorViewTransform.test.ets)覆盖坐标变换和限幅。 |
| 管理方案：在列表查看名称、模板、更新时间和缩略图，打开或确认删除指定方案；可手动保存，离开编辑页时也会确认保存，再打开可继续编辑。 | FR-12～15；[方案库](../entry/src/main/ets/components/plan/PlanLibrary.ets)、[缩略图](../entry/src/main/ets/components/plan/PlanThumbnail.ets)、[保存协调](../entry/src/main/ets/application/SaveCoordinator.ets) | UX03-07、08：三份方案独立保存和重开，取消及确认删除均通过设备验收。宿主 B-T03 核对[列表副本隔离](../entry/src/test/PlanRepository.test.ets#L283)和[对象保存与读取隔离](../entry/src/test/PlanRepository.test.ets#L311)。另有[取消删除不写入](../entry/src/test/PlanRepository.test.ets#L527)、[确认删除仅移除目标](../entry/src/test/PlanRepository.test.ets#L541)及[保存回执为 Saved](../entry/src/test/SaveCoordinator.test.ets#L257)的宿主断言。 |
| 恢复已保存工作：应用进程结束后重新打开，读取最近一次成功保存的方案；保存状态和异常处理提供反馈。 | FR-14、16～18；[方案仓库](../entry/src/main/ets/repository/PlanRepository.ets)、[本地存储](../entry/src/main/ets/storage/PreferencesStore.ets) | UX03-08：三份方案在受控结束进程后恢复并可继续编辑，设备 PASS；INT-02 核对逐案数据。宿主 B-T02 分别检查[三案重开](../entry/src/test/Persistence.test.ets#L448)和[位置与角度持久化](../entry/src/test/Persistence.test.ets#L474)。B-T06 的[主备损坏](../entry/src/test/Persistence.test.ets#L647)及[主快照 flush 失败](../entry/src/test/Persistence.test.ets#L543)为宿主 Mock，设备破坏性恢复为 NOT RUN。 |

目录中的十类物件为接待台、展示桌、作品展架、互动屏、座椅、储物柜、导视牌、绿植、展品台和立式海报架。

物件视觉与不同细节层级的验收为 UX03-10 PARTIAL；约 388 vp 标准 Phone 窗口下的方案库、输入法和小屏操作为 UX03-11 PASS，具体边界见[已知限制](LIMITATIONS.md)。

项目分工：郑鑫越负责编辑器、几何、历史、视口及集成；贾云翔负责模板、目录、物件视觉、方案库、持久化与恢复。双方模块通过统一方案契约集成。
