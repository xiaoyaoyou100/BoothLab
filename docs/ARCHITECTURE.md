# 系统架构

EntryAbility 通过 Stage 框架加载 pages/Index。Index 管理方案库、存储初始化、编辑页切换以及保存状态。编辑器把触摸位置转换为厘米坐标，提交后的方案通过同一数据契约交给存储模块。目录、编辑器和缩略图共享物件定义及绘制规则。

## 模块架构

~~~mermaid
flowchart TD
    EA["EntryAbility"] --> IDX["Index"]
    IDX --> LIB["PlanLibrary"]
    IDX --> WS["EditorWorkspace"]
    IDX --> SAVE["SaveCoordinator"]
    IDX --> REB["RebuildCoordinator"]
    IDX --> REPO["PlanRepository"]
    SAVE -.->|"通过接口保存"| PORT["PlanRepositoryPort"]
    REPO -.->|"实现接口"| PORT
    IDX -.->|"持有并传递方案"| PLAN["BoothPlan"]
    WS -.->|"接收并回传方案"| PLAN
    REPO -.->|"创建、读取和保存方案"| PLAN
    SAVE -.->|"绑定和更新草稿"| PLAN
    REB -->|"由 Index 绑定回调"| REPO
    REPO --> SER["PlanSerializer / PlanValidator"]
    REPO --> PREF["PreferencesStore"]
    WS --> CTRL["EditorController"]
    WS --> PICK["ObjectCatalogPicker"]
    LIB --> CARD["TemplateCard"]
    LIB --> THUMB["PlanThumbnail"]
    class WS,CTRL editor
    class LIB,REPO,PREF,SER,PICK,CARD,THUMB library
    class EA,IDX,SAVE,REB,PLAN,PORT shared
    classDef editor fill:#dbeafe,stroke:#2563eb,color:#172554
    classDef library fill:#dcfce7,stroke:#15803d,color:#052e16
    classDef shared fill:#f1f5f9,stroke:#475569,color:#0f172a
~~~

蓝色标注郑鑫越负责的编辑器与控制器，绿色标注贾云翔负责的方案库、目录和持久化模块，灰色标注应用集成与共享契约。实线表示页面调用或组件关系，虚线表示数据类型或接口依赖。

| 职责 | 实现位置 | 成员 |
| --- | --- | --- |
| Stage 入口与页面串接 | [EntryAbility](../entry/src/main/ets/entryability/EntryAbility.ets)、[Index](../entry/src/main/ets/pages/Index.ets) | 郑鑫越负责系统集成，贾云翔提供方案库与持久化接口 |
| Canvas、坐标、交互和校验 | [EditorWorkspace](../entry/src/main/ets/components/editor/EditorWorkspace.ets)、[EditorController](../entry/src/main/ets/engine/EditorController.ets)、[GeometryEngine](../entry/src/main/ets/engine/GeometryEngine.ets)、[LayoutValidator](../entry/src/main/ets/engine/LayoutValidator.ets)、[EditorViewTransform](../entry/src/main/ets/components/editor/EditorViewTransform.ets) | 郑鑫越 |
| 模板、目录、缩略图和俯视图 | [BoothTemplates](../entry/src/main/ets/catalog/BoothTemplates.ets)、[ObjectCatalogData](../entry/src/main/ets/catalog/ObjectCatalogData.ets)、[ObjectVisuals](../entry/src/main/ets/components/catalog/ObjectVisuals.ets)、[PlanThumbnail](../entry/src/main/ets/components/plan/PlanThumbnail.ets) | 贾云翔 |
| 命名、预览、保存与恢复 | [PlanLibrary](../entry/src/main/ets/components/plan/PlanLibrary.ets)、[PlanRepository](../entry/src/main/ets/repository/PlanRepository.ets)、[PreferencesStore](../entry/src/main/ets/storage/PreferencesStore.ets) | 贾云翔负责库与存储，郑鑫越负责编辑和恢复界面集成 |
| 公共契约 | [BoothModels](../entry/src/main/ets/model/BoothModels.ets)、[M2Contracts](../entry/src/main/ets/model/M2Contracts.ets) | BoothPlan 表示展位方案数据，PlanRepositoryPort 定义方案仓库接口。 |

## 创建和加载方案

1. 从方案库新建时，创建回调交给 [Index.handleCreate](../entry/src/main/ets/pages/Index.ets#L567)。它先调用 [PlanRepository.createPlan](../entry/src/main/ets/repository/PlanRepository.ets#L860)。仓库去除名称首尾空白、核对模板，并持久化物件列表为空的新方案。
2. 创建成功后，Index 通过 [openPlan](../entry/src/main/ets/repository/PlanRepository.ets#L908) 打开新方案。重开已有方案从 [Index.handleOpen](../entry/src/main/ets/pages/Index.ets#L598) 进入，同样由 openPlan 保存当前方案 ID 并返回方案副本。
3. 打开成功后，Index 调用 [enterEditor](../entry/src/main/ets/pages/Index.ets#L657)，用 [SaveCoordinator.bind](../entry/src/main/ets/application/SaveCoordinator.ets#L52) 绑定方案。草稿可用后，页面切到编辑器。

目录选择经 EditorWorkspace 交给 EditorController。放置校验通过后，物件加入方案并形成一条历史记录。撤销或重做恢复相应的物件状态并重新计算布局问题。有效编辑、撤销和重做都会更新编辑会话及协调器草稿。持久化写入由手动保存或离页保存触发。

## 编辑操作数据流

~~~mermaid
flowchart TD
    WS["EditorWorkspace"] -->|"用视口变换换算触点"| GEO["GeometryEngine.screenToWorld"]
    WS -->|"把厘米坐标传给拖动方法"| CTRL["EditorController"]
    CTRL -->|"beginDrag / updateDrag"| PRE["拖动预览"]
    CTRL -->|"endDrag / 添加 / 直接移动 / 旋转"| CHECK["LayoutValidator.canPlace"]
    CHECK -->|"允许放置"| COMMIT["EditorController 提交正式变更"]
    CHECK -->|"非法位置"| ERR["操作反馈"]
    CTRL -->|"删除已有物件"| COMMIT
    COMMIT -->|"记录前后状态"| HIST["HistoryManager.record"]
    COMMIT -->|"推进会话版本"| WS
    WS -->|"核对版本"| NOTIFY["EditorChangeNotifier"]
    WS -->|"有版本变更时通过 onChanged 传递 BoothPlan"| IDX["Index.handleEditorChanged"]
    IDX --> SAVE["SaveCoordinator.update"]
~~~

EditorController 维护已提交对象和临时拖动状态。HistoryManager 保存物件数组的变更前后副本，容量为 50。新编辑清除重做分支，撤销或重做后会重新计算布局问题。选中、拖动预览和视口操作均保持正式方案数据独立。GeometryEngine 计算旋转后的占地及矩形相交，LayoutValidator 把越界与禁止区作为放置约束，并报告重叠或入口预留区占用。[历史管理](../entry/src/main/ets/engine/HistoryManager.ets) · [变更通知](../entry/src/main/ets/application/EditorChangeNotifier.ets)

## 方案保存与恢复

~~~mermaid
flowchart TD
    A["Index: 手动保存或离开编辑"] --> B["SaveCoordinator.save"]
    B --> C["PlanRepository.savePlan"]
    C --> D["PlanValidator / PlanSerializer"]
    D --> E["PreferencesStore: 先写已有确认快照至备份，再写主快照"]
    E -->|"持久化确认"| F["发布成功方案和保存状态"]
    I["Index 初始化"] --> J["PlanRepository.recoverStore"]
    J --> K["读取并验证主快照"]
    K -->|"合法，且备份探测允许"| L["载入主快照"]
    K -->|"缺失或损坏"| M["读取并验证备份"]
    M -->|"有效"| N["返回已恢复方案"]
    M -->|"双缺失"| O["首次启动空库"]
    M -->|"读取失败、未来版本或其他无法恢复状态"| Q
    M -->|"主备均损坏且满足重建条件"| P["保留旧值，提供受保护重建入口"]
    K -->|"未来版本或读取错误"| Q["返回保护性错误"]
    P --> R["RebuildCoordinator: 确认后请求仓库归档并重建"]
~~~

SaveCoordinator 对当前编辑草稿做快照，使用修订号和会话标记处理延迟回执。PlanRepository 串行执行写入，写入成功才发布候选状态。PreferencesStore 在有已确认快照时先写并 flush 备份，再写并 flush 主快照。进程重启读取成功保存的方案，撤销栈和视图属于当前编辑会话。双损坏重建需要显式确认和归档校验。真实设备的破坏性注错与重装仍为 NOT RUN。[保存协调](../entry/src/main/ets/application/SaveCoordinator.ets) · [重建协调](../entry/src/main/ets/application/RebuildCoordinator.ets) · [恢复限制](LIMITATIONS.md)

## 目录、绘制与测试协作

~~~mermaid
flowchart LR
    T["BoothTemplates"] --> REPO["PlanRepository"]
    T --> CTRL["EditorController"]
    C["ObjectCatalogData"] --> CTRL
    WS["EditorWorkspace"] -->|"传入目录数据"| PICK["ObjectCatalogPicker"]
    C --> WS
    C --> TH["PlanThumbnail"]
    WS --> VIS["ObjectVisuals"]
    PICK --> VIS
    TH --> VIS
    CTRL --> LV["LayoutValidator"]
    LV --> GE["GeometryEngine"]
    REPO --> PORT["SnapshotStorage"]
    PORT --- PS["PreferencesStore"]
    PORT --- MS["MemorySnapshotStorage"]
~~~

BoothPlan 记录模板 ID、方案元数据和物件。PlacedObject 记录实例 ID、目录 ID、中心坐标、旋转和层次。PlanStore 保存 schemaVersion、方案列表和当前方案 ID。默认 Hypium 从 List.test.ets 汇集编辑、几何、仓库与保存等测试。存储异常用宿主替身覆盖，独立视口数学走另一条入口，设备集成场景见测试证据。[默认测试入口](../entry/src/test/List.test.ets) · [测试指南](TESTING.md)
