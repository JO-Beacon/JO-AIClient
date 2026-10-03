/* JO-AIClient 官网 —— 首屏“Windows 桌面版”交互模拟器
   纯前端内存状态，不连任何后台；每个按钮都是真实状态变更。 */

(function () {
  'use strict';

  var win = document.getElementById('win');
  // 最大化时要把窗口挂到 body 下：它的祖先 .hero__grid 有 position: relative + z-index: 1，
  // 会建立层叠上下文，把窗口的 z-index 困在里面，导致站点顶栏压在窗口标题栏之上。
  var winHome = win.parentNode;
  // 还原时必须插回原位：容器里窗口后面还有示意图说明与辅助示意卡，
  // 直接 appendChild 会把窗口排到它们后面，布局就乱了。
  var winNext = win.nextSibling;
  var appThemeAnimTimer = null;
  var rail = document.getElementById('rail');
  var listEl = document.getElementById('sbarList');
  var mainEl = document.getElementById('cchat');
  var treeEl = document.getElementById('heroTree');
  var queryEl = document.getElementById('sbarQuery');

  /* 「跟随网页」：模拟器不自己去看系统偏好，而是直接跟网页当前的深浅色。
     这样它嵌在页面里不会跟页面脱节；而网页主题本身就包含「跟随系统」，
     所以这条路间接也跟了系统。用观察器盯住 <html> 的主题属性，
     不依赖 app.js 主动通知。 */
  new MutationObserver(function () {
    if (S.appTheme === 'page') render();
  }).observe(document.documentElement, {
    attributes: true,
    attributeFilter: ['data-theme'],
  });
  if (!win || !listEl || !mainEl || !treeEl) return;

  /* ============================ 数据 ============================ */

  /* 助手自带会话列表：真机里「话题」页显示的是当前助手的会话。
     第一助手的首条会话就是页面下方“示例 A”的同一份内容，其余为短示例。 */
  var ASSISTANTS = [
    {
      id: 'a1', name: '通用助手', av: '通',
      topics: [
        { id: 'a1t1', name: '快速排序的分区逻辑', av: '快', demo: true },
        {
          id: 'a1t2', name: '查询接口加一层缓存', av: '缓',
          q: '给这个查询接口加一层缓存，别每次都打数据库。',
          a: '常见有三种做法：内存 Map、TTL + LRU、交给 HTTP 缓存。并发回源用 single-flight 收敛，避免缓存刚失效时把请求全打到数据库。'
        },
        {
          id: 'a1t3', name: '页面状态管理重构', av: '状',
          q: '把这个页面的 setState 重构为可测试的状态管理方案。',
          a: '先把“输入 → 状态 → 输出”拆开，把副作用收进可注入的依赖，再针对状态迁移写单元测试；界面只负责渲染。'
        }
      ]
    },
    {
      id: 'a2', name: '代码助手', av: '代',
      topics: [
        {
          id: 'a2t1', name: 'Dart 空安全迁移', av: '空',
          q: '这次空安全迁移的重点是什么？',
          a: '重点是把可空性表达在类型上，而不是靠运行时判空；迁移顺序建议从叶子模块往上，逐层收敛。'
        },
        {
          id: 'a2t2', name: '代码评审清单', av: '评',
          q: '给我一份代码评审清单。',
          a: '看四件事：接口边界是否清楚、错误路径有没有交代、并发与生命周期是否安全、测试是否覆盖失败分支。'
        }
      ]
    },
    {
      id: 'a3', name: '写作助手', av: '写',
      topics: [
        {
          id: 'a3t1', name: '发布说明的结构', av: '发',
          q: '发布说明应该怎么组织？',
          a: '先说用户能感知到的变化，再按需补充原因；内部标识符与架构术语能不用就不用。'
        }
      ]
    },
    {
      id: 'a4', name: '翻译助手', av: '译',
      topics: [
        {
          id: 'a4t1', name: '技术文档翻译风格', av: '译',
          q: '技术文档翻译要注意什么？',
          a: '术语先统一再动笔，命令、路径与标识符保持原样；句子按目标语言的语序重写，不做逐词对译。'
        }
      ]
    },
    {
      id: 'a5', name: '数据分析', av: '数',
      topics: [
        {
          id: 'a5t1', name: '留存率的读法', av: '留',
          q: '留存率该怎么读？',
          a: '先固定队列口径与时间窗，再看曲线的收敛位置；对比不同版本时别混用口径，否则数字不可比。'
        }
      ]
    },
    {
      id: 'a6', name: '学习辅导', av: '学',
      topics: [
        {
          id: 'a6t1', name: '理解递归的思路', av: '递',
          q: '怎么理解递归？',
          a: '先写清楚“最小情形返回什么”，再假定更小规模已经解决，只描述当前这一步怎么用它的结果。'
        }
      ]
    },
    {
      id: 'a7', name: '会议纪要', av: '会',
      topics: [
        {
          id: 'a7t1', name: '会议纪要的要点', av: '要',
          q: '会议纪要该记哪些内容？',
          a: '结论、待办、负责人、截止时间；讨论过程只保留影响结论的分歧。'
        }
      ]
    },
    {
      id: 'a8', name: '产品评审', av: '评',
      topics: [
        {
          id: 'a8t1', name: '需求评审提纲', av: '需',
          q: '需求评审该问哪些问题？',
          a: '解决谁的什么问题、不做会怎样、边界情况怎么处理、怎么验证做对了。'
        }
      ]
    }
  ];

  /* 演示内容与页面下方的“示例 A”保持一致，均为通用示例，不含任何个人数据。 */
  var CHAT = {
    title: '快速排序的分区逻辑',
    av: '快',
    model: '模型-X',
    provider: '供应商-A',
    question: '用 Dart 写一个快速排序，并解释分区逻辑。',
    branches: [
      {
        tag: '首次生成 · 14:02',
        think: '',
        thinkSub: '',
        text: '三路分区：小于 / 等于 / 大于各一段，等于段一次落位。直观，但每层都新建列表。',
        code: 'List<int> quickSort(List<int> a) {\n' +
          '  if (a.length <= 1) return a;\n' +
          '  final pivot = a[a.length ~/ 2];\n' +
          '  final lo = <int>[], eq = <int>[], hi = <int>[];\n' +
          '  for (final x in a) {\n' +
          '    if (x < pivot) lo.add(x);\n' +
          '    else if (x > pivot) hi.add(x);\n' +
          '    else eq.add(x);\n' +
          '  }\n' +
          '  return [...quickSort(lo), ...eq, ...quickSort(hi)];\n' +
          '}'
      },
      {
        tag: '重新生成 · 14:05',
        think: '深度思考 2.8s',
        thinkSub: '基准选择 · 原地交换 · 递归深度',
        text: 'Lomuto 原地分区：i 左侧是已确认的小于区，扫描结束后把基准换到 i，基准即落在最终位置。',
        code: 'void quickSort(List<int> a, [int lo = 0, int hi = -1]) {\n' +
          '  hi = hi < 0 ? a.length - 1 : hi;\n' +
          '  if (lo >= hi) return;\n' +
          '  final pivot = a[hi];\n' +
          '  var i = lo;\n' +
          '  for (var j = lo; j < hi; j++) {\n' +
          '    if (a[j] < pivot) {\n' +
          '      final t = a[i]; a[i] = a[j]; a[j] = t; i++;\n' +
          '    }\n' +
          '  }\n' +
          '  final t = a[i]; a[i] = a[hi]; a[hi] = t;\n' +
          '  quickSort(a, lo, i - 1);\n' +
          '  quickSort(a, i + 1, hi);\n' +
          '}'
      },
      {
        tag: '重新生成 · 14:09',
        think: '',
        thinkSub: '',
        text: '先说结论：生产代码更推荐直接 list.sort()。若要自己实现，注意三点：基准选择——固定取末尾在已排序输入上退化为 O(n²)；相等元素——三路分区收益明显；递归深度——先递归短侧、长侧改循环，可压到 O(log n)。',
        code: ''
      }
    ],
    /* 分支 2 里又追问了一轮，因此这一支自己再分一次叉：
       树是两层嵌套，与真实的消息级分支模型一致。 */
    followUp: {
      parentIndex: 1,
      question: '那工程上到底该用三路分区，还是 Lomuto 原地分区？',
      branches: [
        {
          tag: '首次生成 · 14:12',
          think: '',
          thinkSub: '',
          text: '先看数据分布：重复元素多就用三路分区，几乎不重复且在意内存就用 Lomuto。两者平均复杂度同为 O(n log n)，差别在常数与最坏情况。',
          code: ''
        },
        {
          tag: '重新生成 · 14:16',
          think: '深度思考 1.6s',
          thinkSub: '基准随机化 · 短侧优先递归 · 最坏情况',
          text: '多数场景直接调用库里的排序即可；必须自己实现时，把基准随机化、先递归较短的一侧，最坏情况就能压下去。',
          code: ''
        }
      ]
    },
    menu: [
      { act: 'edit', label: '编辑' },
      { act: 'fork', label: '创建消息分支' },
      { act: 'del-one', label: '删除此条消息' },
      { act: 'del-after', label: '删除此消息及后续' },
      { act: 'del-node', label: '删除此分支节点' },
      { act: 'del-branch', label: '删除当前分支' },
      { act: 'del-all', label: '删除所有分支' }
    ]
  };

  var PAGES = {
    chat: null,
    search: { h: '全局搜索', p: '在标题与消息里搜索全部会话。演示版不连数据，这里只作占位。' },
    translate: { h: '翻译', p: '独立的翻译页。演示版只作占位。' },
    storage: { h: '存储空间', p: '查看本机数据占用与清理入口。演示版只作占位。' },
    settings: { h: '设置', p: '供应商、助手、外观、备份等设置入口。演示版只作占位。' }
  };

  /* ============================ 状态 ============================ */

  var S = {
    page: 'chat',
    tab: 'assistant',
    query: '',
    sort: false,
    sidebarOpen: true,
    hideCanned: false,
    assistantId: 'a1',
    topicId: 'a1t1',
    /* 侧栏默认宽度。应用首次运行是 300，但模拟窗口嵌在网页里只有 ~800px 宽，
       应用真实默认值是 300（设置项 desktop_sidebar_width_v1 读取时是「已存值 ?? 300」），
       但模拟窗口嵌在网页里只有约 815px 宽，300 会把会话区挤没，所以这里取 240。
       这是为网页布局做的取舍（plans 文档第 2 节「有意为之的偏差」已登记，别改回 300）。
       拖拽范围仍按应用（200–360）。
       这是为网页布局做的取舍，不是还原失误。拖拽范围仍按应用（200–360）。 */
    sidebarWidth: 240,
    branch: 1,
    branch2: 0,
    appended: [], // 发送后追加的消息 {role,text}
    menuOpen: false,
    menuLevel: 1,
    status: '切换分支时，只有当前活动分支的内容会显示在对话区。',
    note: '',
    editingTitle: false,
    appTheme: 'page', // 模拟界面自己的主题：跟随网页 / 浅色 / 深色，与网页主题开关互不影响
    win: 'normal', // normal | max | min | closed
    tools: {},
    composerMenu: null // 输入条上打开的小面板：动作 id 或 'more'
  };

  function activeChat() {
    return S.page === 'chat' || S.page === 'search';
  }

  function curAssistant() {
    for (var i = 0; i < ASSISTANTS.length; i++) {
      if (ASSISTANTS[i].id === S.assistantId) return ASSISTANTS[i];
    }
    return ASSISTANTS[0];
  }

  function curTopic() {
    var list = curAssistant().topics;
    for (var i = 0; i < list.length; i++) {
      if (list[i].id === S.topicId) return list[i];
    }
    return list[0];
  }

  /* 第一层是首轮回答的三条分支；第二层只在其中一条分支里存在。 */
  function levelBranches(level) {
    return level === 2 ? CHAT.followUp.branches : CHAT.branches;
  }

  function levelIndex(level) {
    return level === 2 ? S.branch2 : S.branch;
  }

  function setLevelIndex(level, i) {
    if (level === 2) S.branch2 = i; else S.branch = i;
  }

  /* ============================ 渲染 ============================ */

  /* 头部左上角的列表面板图标：应用使用仓库自带的 assets/icons/list.svg */
  // 列表按钮的图标：真机用仓库的 assets/icons/list.svg，尺寸 14×14
  var ICON_LIST = '<svg width="14" height="14" viewBox="0 0 20 16" fill="currentColor" aria-hidden="true"><rect x="0" y="2.4" width="20" height="2.2" rx="1.1"/><rect x="0" y="11.4" width="13" height="2.2" rx="1.1"/></svg>';
  var ICON_PLUS = '<span class="lic lic-message-circle-plus"></span>';
  var ICON_MONITOR = '<span class="lic lic-monitor"></span>';
  var ICON_SUN = '<span class="lic lic-sun"></span>';
  var ICON_MOON = '<span class="lic lic-moon"></span>';

  function esc(s) {
    return String(s).replace(/[&<>"]/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c];
    });
  }

  function appThemeEffective() {
    if (S.appTheme === 'light' || S.appTheme === 'dark') return S.appTheme;
    return document.documentElement.getAttribute('data-theme') === 'light' ? 'light' : 'dark';
  }

  function renderRail() {
    Array.prototype.forEach.call(rail.querySelectorAll('.rail__ico'), function (b) {
      var p = b.getAttribute('data-page');
      var on = p === 'theme' ? false : p === S.page;
      b.classList.toggle('is-on', on);
    });
    var themeBtn = rail.querySelector('[data-page="theme"]');
    if (themeBtn) {
      themeBtn.innerHTML = S.appTheme === 'light' ? ICON_SUN : S.appTheme === 'dark' ? ICON_MOON : ICON_MONITOR;
      var lbl = S.appTheme === 'light' ? '浅色' : S.appTheme === 'dark' ? '深色' : '跟随网页';
      themeBtn.title = '界面主题：' + lbl + '（点击切换）';
    }
    // 图标轨道顶部是应用自己的 logo，静态写在 index.html 里（原来这里每次渲染写死字母 J，会把 logo 覆盖掉）
  }

  function renderSidebar() {
    renderTabs();
    var isAssistantTab = S.tab === 'assistant';
    var src = isAssistantTab ? ASSISTANTS : curAssistant().topics;
    var selected = isAssistantTab ? S.assistantId : S.topicId;
    if (queryEl) queryEl.placeholder = isAssistantTab ? '搜索助手' : '搜索当前助手';
    var q = S.query.trim().toLowerCase();
    var rows = src.filter(function (x) {
      return !q || x.name.toLowerCase().indexOf(q) >= 0;
    });
    if (S.sort) {
      rows = rows.slice().sort(function (a, b) { return a.name.localeCompare(b.name, 'zh'); });
    }
    // 真机侧栏按日期分组：今天 / 昨天 / M月d日，组标题 14px、semibold、主色，
    // 内距 14/6/0/6（side_drawer.dart 约 4077 行的 _SidebarHeaderRow 渲染）。
    // 演示数据没有真实时间，按顺序分配：前 2 条今天、接着 2 条昨天、其余 6月2日。
    // 搜索时不分段（与真机搜索结果一致）。
    var showGroups = !isAssistantTab && !q;
    var bucketOf = function (i) { return i < 2 ? '今天' : (i < 4 ? '昨天' : '6月2日'); };
    listEl.innerHTML = rows.length
      ? rows.map(function (x, i) {
          var head = '';
          if (showGroups && (i === 0 || bucketOf(i - 1) !== bucketOf(i))) {
            head = '<li class="sbar__group">' + bucketOf(i) + '</li>';
          }
          return head + '<li class="sbar__item' + (x.id === selected ? ' is-on' : '') + '" data-id="' + x.id + '" data-name="' + esc(x.name) + '">' +
            '<span class="sbar__av">' + esc(x.av) + '</span>' +
            '<span class="sbar__name">' + esc(x.name) + '</span></li>';
        }).join('')
      : '<li class="sbar__empty">没有匹配的' + (isAssistantTab ? '助手' : '话题') + '</li>';
  }

  function renderTabs() {
    Array.prototype.forEach.call(document.querySelectorAll('.sbar__tab'), function (b) {
      b.classList.toggle('is-on', b.getAttribute('data-tab') === S.tab);
    });
  }

  /* 用户消息头部：昵称 + 时间 + 头像，右对齐（真机截图） */
  function userHead() {
    return '<div class="cmsg-head">' +
      '<span class="cmsg-head__n">我</span>' +
      '<span class="cmsg-head__t">2026-06-02 18:32:31</span>' +
      '<span class="cmsg-av">我</span>' +
    '</div>';
  }

  /* 深度思考卡片。真机默认是「收起」——只显示一行标题与折角
     （chat_message_widget.dart 的 reasoningExpanded 默认 false），点标题展开；
     折角图标在 ChevronUp / ChevronDown 之间切换。 */
  function thinkBox(b) {
    if (!b.think) return '';
    var lines = b.thinkSub ? b.thinkSub.split(' · ') : [];
    var open = S.thinkOpen === true;
    return '<div class="cthink' + (open ? ' is-open' : '') + '">' +
      '<button type="button" class="cthink__h" data-think="1">' +
        '<span class="lic lic-sparkles cthink__i"></span>' +
        '<span class="cthink__t">' + esc(b.think) + '</span>' +
        '<span class="lic ' + (open ? 'lic-chevron-up' : 'lic-chevron-down') + ' cthink__c"></span>' +
      '</button>' +
      (lines.length
        ? '<ul class="cthink__l">' + lines.map(function (l) { return '<li>' + esc(l) + '</li>'; }).join('') + '</ul>'
        : '') +
      '</div>';
  }

  /* 输入条工具行。
     取值出处：lib/features/home/widgets/chat_input_bar.dart
     - 左侧 15 个动作与顺序取自 _buildResponsiveLeftActions
     - 右侧取自桌面分支：展开/收起（Plus 与 X 互切）、上下文用量环、麦克风、发送
     - 按钮 32、间距 8（同文件 2128 行的 spacing 与 normalButtonW）
     - 量环 32（lib/shared/widgets/context_usage_ring.dart 的 kContextUsageRingHitSize）
     - 发送 32（图标 18 + 内距 7×2）
     真机放不下时会把末尾动作移进「+」菜单，这里用同样的规则按可用宽度算。
     搜索按钮在真机里会显示供应商品牌图标，网站不放品牌 logo，改用通用搜索图标。 */
  var CT_BTN = 32, CT_GAP = 8;
  var CT_RIGHT = 32 + 8 + 32 + 8 + 32 + 8 + 32; // 展开/收起、量环、麦克风、发送

  var COMPOSER_ACTIONS = [
    // 名称与顺序取自 chat_input_bar.dart 的 _buildResponsiveLeftActions；
    // 显示与否取自 chat_input_section.dart 的传参（isTablet / isDesktop / 是否配置）。
    // 这里是「Windows 桌面 + 宽布局 + 演示会话」的取值：没有绑定工作区、没有快捷短语、
    // 没有世界书、没配 OCR 模型、没配语音识别服务，因此那几项都不出现；
    // 拍照与相册在桌面系统上恒为 null，也不出现。
    ['model', 'lic-boxes', '选择模型', 'menu', '真机在这里显示当前模型的品牌图标。演示版用通用图标。'],
    ['search', 'lic-globe', '联网搜索', 'toggle', '让模型在回答前先联网检索。'],
    ['reason', 'lic-brain', '推理强度', 'menu', '演示版：这里会打开推理强度档位。'],
    ['skill', 'lic-wand-2', '技能', 'menu', '演示版：这里会列出当前会话可用的技能。'],
    ['tools', 'lic-tool-case', '本地工具与 MCP', 'menu', '演示版：这里会打开本地工具与 MCP 服务器。'],
    ['upload', 'lic-paperclip', '上传文件', 'menu', '演示版：真机会选择文件作为附件。'],
    ['inject', 'lic-layers-2', '指令注入', 'menu', '演示版：这里会打开指令注入设置。'],
    ['context', 'lic-eraser', '上下文管理', 'menu', '演示版：这里会打开上下文管理与压缩。'],
    ['minimap', 'lic-map', '小地图', 'menu', '演示版：这里会打开会话分支小地图。']
  ];

  /* 渲染后按真实宽度调整：先全部画出，量到左行装不下时，把末尾动作从 DOM 里
     摘下来交给「+」，并让「+」出现。真机也是先量再决定（LayoutBuilder）。 */
  var CT_OVERFLOW = [];

  function applyComposerOverflow() {
    var row = document.querySelector('.composer__tools-left');
    if (!row) return;
    var plus = row.querySelector('.ctool--more');
    var acts = row.querySelectorAll('.ctool[data-caction]');
    if (!acts.length) { if (plus) plus.hidden = true; return; }
    var room = row.clientWidth;
    var keep = 0, used = 0;
    for (var i = 0; i < acts.length; i++) {
      var w = CT_BTN + (i ? CT_GAP : 0);
      var needPlus = (i + 1) < acts.length; // 还剩动作，就要留出「+」的位置
      if (used + w + (needPlus ? CT_GAP + CT_BTN : 0) <= room) { used += w; keep = i + 1; }
      else break;
    }
    if (keep >= acts.length) { if (plus) plus.hidden = true; CT_OVERFLOW = []; return; }
    CT_OVERFLOW = [];
    for (var j = acts.length - 1; j >= keep; j--) {
      CT_OVERFLOW.unshift(acts[j].getAttribute('data-caction'));
      acts[j].parentNode.removeChild(acts[j]);
    }
    if (plus) plus.hidden = false;
    // 溢出清单刚算出来：弹层若已打开，就在这里补建或刷新（只改弹层，不动输入框）
    if (S.composerMenu) {
      var items = composerPopItems();
      var pop = document.getElementById('composerPop');
      if (!items.length) {
        if (pop) pop.parentNode.removeChild(pop);
      } else if (pop) {
        pop.innerHTML = composerPopInner(items, S.composerMenu !== 'more');
      } else {
        var toolsBox = row.parentNode;         // .composer__tools
        var composerEl = toolsBox.parentNode;  // .composer
        pop = document.createElement('ul');
        pop.className = 'cmenu cmenu--composer';
        pop.id = 'composerPop';
        pop.innerHTML = composerPopInner(items, S.composerMenu !== 'more');
        composerEl.insertBefore(pop, toolsBox);
      }
    }
  }

  function composerVisibleCount() {
    // 首帧宽度还没定，先全部画出来，交给 applyComposerOverflow 收尾
    return COMPOSER_ACTIONS.length;
  }

  function composerToolButton(a) {
    var on = a[3] === 'toggle' && S.tools[a[0]] ? ' is-on' : '';
    var cls = 'ctool' + (a[0] === 'model' ? ' ctool--model' : '') + on;
    return '<button type="button" class="' + cls + '" data-caction="' + a[0] +
      '" title="' + a[2] + '"><span class="lic ' + a[1] + '"></span></button>';
  }

  function composerActionsHtml() {
    return COMPOSER_ACTIONS.map(composerToolButton).join('') +
      // 真机桌面布局下 showMoreButton = !isTablet 为假，不显示这个「更多」＋
      // （chat_input_section.dart:266），溢出时由响应式动作列表自行取舍。
      '';
  }

  function composerPopItems() {
    if (!S.composerMenu) return [];
    if (S.composerMenu === 'more') {
      return COMPOSER_ACTIONS.filter(function (a) { return CT_OVERFLOW.indexOf(a[0]) >= 0; });
    }
    return COMPOSER_ACTIONS.filter(function (a) { return a[0] === S.composerMenu; });
  }

  /* 溢出菜单按真机的样子：只有图标与名称（真机用的是 DesktopContextMenuItem）。
     单个动作的弹层才带一行说明，说明文字是演示版自述，不是真机文案。 */
  function composerPopInner(items, withNote) {
    return items.map(function (a) {
      var on = a[3] === 'toggle' && S.tools[a[0]] ? '<em>已开启</em>' : '';
      return '<li><button type="button" data-caction="' + a[0] + '">' +
        '<span class="lic ' + a[1] + '"></span>' + a[2] + on + '</button>' +
        (withNote ? '<span class="cmenu__note">' + a[4] + '</span>' : '') + '</li>';
    }).join('');
  }

  function composerPopHtml() {
    if (!S.composerMenu) return '';
    var items = composerPopItems();
    if (!items.length) return '';
    return '<ul class="cmenu cmenu--composer" id="composerPop">' + composerPopInner(items, S.composerMenu !== 'more') + '</ul>';
  }

  function composerHtml() {
    // 量环里的百分比是演示值：真机按当前会话实际占用计算。
    // 外层间距 12/4/12/8 与最大宽度 860、居中：出处 ChatInputBar.build 的
    // Padding(fromLTRB(sm,xxs,sm,xs)) 与 home_page 里 Align + ConstrainedBox(maxInputWidth)
    return '<div class="composer-wrap">' +
      '<div class="composer">' +
      '<div class="composer__in-wrap">' +
        '<textarea class="composer__in" id="composerInput" rows="1" placeholder="输入消息与AI聊天" autocomplete="off"></textarea>' +
      '</div>' +
      composerPopHtml() +
      '<div class="composer__tools">' +
        '<div class="composer__tools-left">' + composerActionsHtml() + '</div>' +
        // 右侧只有用量环与发送：真机里工具面板开关由 showMoreButton 控制，
        // 宽布局下不显示；麦克风要配了语音识别服务或模型支持音频才出现。
        '<div class="composer__tools-right">' +
          '<button type="button" class="ctool ctool--ring" data-caction="ring" title="上下文用量">' +
            '<span class="cring" style="--p:12"></span></button>' +
          '<button type="button" class="ctool ctool--send" data-send="1" title="发送"><span class="lic lic-arrow-up"></span></button>' +
        '</div>' +
      '</div>' +
      '</div>' +
    '</div>';
  }

  function renderMain() {
    if (!activeChat()) {
      var pg = PAGES[S.page];
      mainEl.innerHTML =
        '<div class="cpage"><h4 class="cpage__h">' + pg.h + '</h4>' +
        '<p class="cpage__p">' + pg.p + '</p>' +
        '<p class="cpage__m">点左侧图标栏可以切回聊天。</p></div>';
      return;
    }
    var assistant = curAssistant();
    var topic = curTopic();
    var head =
      '<div class="cchat__head">' +
        '<button type="button" class="cchat__lead" data-lead="1" title="收起或展开侧栏">' + ICON_LIST + '</button>' +
        '<span class="cchat__av">' + esc(topic.av || assistant.av) + '</span>' +
        (S.editingTitle
          ? '<input class="cchat__title-in" id="titleInput" value="' + esc(topic.name) + '" maxlength="40">'
          : '<span class="cchat__name" title="双击重命名">' + esc(topic.name) + '</span>') +
        '<button type="button" class="cchat__chip" data-chip="1" title="切换模型"><span class="lic lic-boxes cchat__chip-ico"></span>' + esc(CHAT.model) + ' <em>|</em> ' + esc(CHAT.provider) + '</button>' +
        '<button type="button" class="cchat__new" data-new="1" title="新建会话">' + ICON_PLUS + '</button>' +
      '</div>';

    var streamBody = '';
    if (S.hideCanned) {
      if (S.appended.length === 0) {
        streamBody +=
          '<div class="cpage" style="flex:1"><h4 class="cpage__h">新会话</h4>' +
          '<p class="cpage__p">在下面输入内容即可开始。演示版不调用真实模型。</p></div>';
      }
    } else if (topic.demo) {
      streamBody += demoThreadHtml();
    } else {
      streamBody +=
        '<div class="cmsg cmsg--u">' + userHead() + '<p>' + esc(topic.q) + '</p></div>' +
        '<div class="cmsg cmsg--a"><p>' + esc(topic.a) + '</p></div>';
    }
    streamBody += S.appended.map(function (m) {
      return '<div class="cmsg cmsg--' + (m.role === 'user' ? 'u' : 'a') + '"><p>' + esc(m.text) + '</p></div>';
    }).join('');
    mainEl.innerHTML = head +
      '<div class="cstream" id="cstream">' + streamBody + '</div>' +
      /* 滚动导航：真机是四个按钮（scroll_nav_buttons.dart）——
         ChevronsUp 回到顶部、ChevronUp 上一条、ChevronDown 下一条、ChevronsDown 回到最新；
         图标 16、按钮 16+6×2=28、间距 8，容器距右 12、距底 80。 */
      '<div class="cscrollnav">' +
        '<button type="button" class="cscrollnav__b" data-scroll="top" title="回到顶部"><span class="lic lic-chevrons-up"></span></button>' +
        '<button type="button" class="cscrollnav__b" data-scroll="prev" title="上一条"><span class="lic lic-chevron-up"></span></button>' +
        '<button type="button" class="cscrollnav__b" data-scroll="next" title="下一条"><span class="lic lic-chevron-down"></span></button>' +
        '<button type="button" class="cscrollnav__b" data-scroll="bottom" title="回到最新"><span class="lic lic-chevrons-down"></span></button>' +
      '</div>' +
      composerHtml();
    var stream = document.getElementById('cstream');
    if (stream) stream.scrollTop = stream.scrollHeight;
    applyComposerOverflow();
    syncSendState();
    // 最大化／还原会改变窗口宽度，而输入条"放不下就溢出"是按渲染当帧的宽度算的，
    // 那时新布局还没生效。下一帧再重算一次，避免还原后按钮排布错乱。
    if (window.requestAnimationFrame) {
      window.requestAnimationFrame(function () {
        if (!document.querySelector('.composer__tools-left')) return;
        applyComposerOverflow();
      });
    }
    // 最大化时脱离容器，恢复时挂回原位
    if (S.win === 'max') {
      if (win.parentNode !== document.body) document.body.appendChild(win);
    } else if (win.parentNode === document.body) {
      if (winNext && winNext.parentNode === winHome) {
        winHome.insertBefore(win, winNext);
      } else {
        winHome.insertBefore(win, winHome.firstChild);
      }
    }
  }

  /* 一条助手消息：思考块 + 正文 + 代码 + 它所在层的分支控件 */
  /* 助手消息下方的操作行。真机（截图 + chat_message_widget.dart）：
     左起 复制、重新生成、朗读、翻译、更多（IosIconButton size: 16），
     接着是分支切换 ‹ n/m ›，右端是 token 数。 */
  function branchRow(level, index, count, tag) {
    var attr = level === 2 ? 'data-branch2' : 'data-branch';
    return '<div class="cacts">' +
      '<button type="button" class="cacts__b" title="复制"><span class="lic lic-copy"></span></button>' +
      '<button type="button" class="cacts__b" data-regen="' + level + '" title="重新生成' + (tag ? '（' + esc(tag) + '）' : '') + '"><span class="lic lic-rotate-cw"></span></button>' +
      '<button type="button" class="cacts__b" title="朗读"><span class="lic lic-volume-2"></span></button>' +
      '<button type="button" class="cacts__b" title="翻译"><span class="lic lic-languages"></span></button>' +
      '<button type="button" class="cacts__b" data-menu="' + level + '" title="更多操作"><span class="lic lic-ellipsis"></span></button>' +
      '<span class="cacts__branch">' +
        '<button type="button" class="cacts__b" ' + attr + '="-1"' + (index <= 0 ? ' disabled' : '') + '><span class="lic lic-chevron-left"></span></button>' +
        '<span class="cacts__n">' + (index + 1) + ' / ' + count + '</span>' +
        '<button type="button" class="cacts__b" ' + attr + '="1"' + (index >= count - 1 ? ' disabled' : '') + '><span class="lic lic-chevron-right"></span></button>' +
      '</span>' +
      '<span class="cacts__tok">18532 tokens</span>' +
    '</div>';
  }

  function aiMsg(b, level, index, count) {
    return '<div class="cmsg cmsg--a">' +
      /* 助手消息头部：品牌图标 + 模型名 | 提供方，下一行是时间（真机截图） */
      '<div class="cmsg-head cmsg-head--a">' +
        /* 真机这里是提供方品牌图标；未知提供方回退到 Lucide.Boxes（与源码一致） */
        '<span class="lic lic-boxes cmsg-head__i"></span>' +
        '<span class="cmsg-head__m">' + esc(CHAT.model) + '</span>' +
        '<em>|</em>' +
        '<span class="cmsg-head__p">' + esc(CHAT.provider) + '</span>' +
      '</div>' +
      '<div class="cmsg-head__t">2026-06-02 18:32:31</div>' +
      thinkBox(b) +
      '<p>' + esc(b.text) + '</p>' +
      (b.code ? '<pre class="ccode"><code>' + esc(b.code) + '</code></pre>' : '') +
      branchRow(level, index, count, b.tag) +
      (level === S.menuLevel ? ((S.note ? '<p class="cnote">' + esc(S.note) + '</p>' : '') + (S.menuOpen ? renderMenu() : '')) : '') +
    '</div>';
  }

  /* 沿当前活动路径铺开：首轮提问 + 选中分支，如果那条分支里追过问，再铺一层 */
  function demoThreadHtml() {
    var fu = CHAT.followUp;
    var body =
      '<div class="cmsg cmsg--u">' + userHead() + '<p>' + esc(CHAT.question) + '</p></div>' +
      aiMsg(CHAT.branches[S.branch], 1, S.branch, CHAT.branches.length);
    if (S.branch === fu.parentIndex) {
      body += '<div class="cmsg cmsg--u">' + userHead() + '<p>' + esc(fu.question) + '</p></div>' +
        aiMsg(fu.branches[S.branch2], 2, S.branch2, fu.branches.length);
    }
    return body;
  }

  function renderMenu() {
    return '<ul class="cmenu">' +
      CHAT.menu.map(function (m) {
        return '<li><button type="button" data-act="' + m.act + '">' + m.label + '</button></li>';
      }).join('') +
      '</ul>';
  }

  function renderTree() {
    var topic = curTopic();
    var fu = CHAT.followUp;
    var kids;
    if (topic.demo) {
      kids = CHAT.branches.map(function (b, i) {
        var on = i === S.branch;
        var hasChild = on && i === fu.parentIndex;
        var inner = '';
        if (hasChild) {
          inner = '<ul><li class="tli on-path">' +
            '<span class="trow"><span class="tdot tdot--user"></span><span class="tlabel">用户</span></span>' +
            '<ul>' + fu.branches.map(function (b2, j) {
              var on2 = j === S.branch2;
              return '<li class="tli' + (on2 ? ' is-active on-path' : '') + '">' +
                '<span class="trow"><span class="tdot"></span><span class="tlabel">助手</span>' +
                '<span class="tcount">分支 ' + (j + 1) + '</span>' +
                (on2 ? '<span class="tnow">当前</span>' : '') +
                '</span></li>';
            }).join('') + '</ul></li></ul>';
        }
        return '<li class="tli' + (on ? ' on-path' : '') + (on && !hasChild ? ' is-active' : '') + '">' +
          '<span class="trow"><span class="tdot"></span><span class="tlabel">助手</span>' +
          '<span class="tcount">分支 ' + (i + 1) + '</span>' +
          (on && !hasChild ? '<span class="tnow">当前</span>' : '') +
          '</span>' + inner + '</li>';
      }).join('');
    } else {
      kids = '<li class="tli is-active on-path">' +
        '<span class="trow"><span class="tdot"></span><span class="tlabel">助手</span>' +
        '<span class="tnow">当前</span></span></li>';
    }
    treeEl.innerHTML =
      '<ul><li class="tli on-path">' +
        '<span class="trow"><span class="tdot tdot--user"></span><span class="tlabel">用户</span></span>' +
        '<ul>' + kids + '</ul>' +
      '</li></ul>' +
      (topic.demo && S.appended.some(function (m) { return m.role === 'user'; })
        ? '<p class="tree__note">发送后会在当前分支下继续。</p>' : '');
  }

  /* 用 Web Animations API 播「旧位置 → 新位置」的补间。
     先把旧位置作为关键帧起点（此时元素已在新布局上），再播到原位。
     浏览器直接播关键帧，不需要 void offsetWidth 这类手动回流，也不依赖同帧时序。
     浏览器不支持 animate() 时跳过动画，状态切换照常生效。 */
  function animateWindowFlip(from) {
    if (!from || from.width < 1 || from.height < 1) return;
    var to = win.getBoundingClientRect();
    if (to.width < 1 || to.height < 1) return;
    var same =
      Math.abs(from.left - to.left) < 1 &&
      Math.abs(from.top - to.top) < 1 &&
      Math.abs(from.width - to.width) < 1 &&
      Math.abs(from.height - to.height) < 1;
    if (same) return;
    if (typeof win.animate !== 'function') return;
    var start =
      'translate(' + (from.left - to.left) + 'px, ' + (from.top - to.top) + 'px) ' +
      'scale(' + (from.width / to.width) + ', ' + (from.height / to.height) + ')';
    win.animate(
      [
        { transformOrigin: 'top left', transform: start },
        { transformOrigin: 'top left', transform: 'none' },
      ],
      { duration: 280, easing: 'cubic-bezier(.22,.61,.36,1)', fill: 'none' },
    );
  }

  function render() {
    // 最大化／还原要动画：元素从文档流切换成 position: fixed，这段不可补间。
    // 所以在改状态之前量旧位置，全部渲染完（DOM 已是新布局）再播 FLIP。
    var flipFrom = win.getBoundingClientRect();
    var flipNeeded =
      S._lastWin !== undefined &&
      S._lastWin !== S.win &&
      (S.win === 'max' || S._lastWin === 'max');
    S._lastWin = S.win;
    // 用 classList 逐个切换，不用整串 className 赋值，
    // 否则会把动画类（app-theme-anim）冲掉。
    win.classList.toggle('is-max', S.win === 'max');
    win.classList.toggle('is-min', S.win === 'min');
    win.classList.toggle('is-closed', S.win === 'closed');
    win.classList.toggle('is-collapsed', !S.sidebarOpen);
    // 最大化后标题栏那个按钮要变成「还原」（真机行为）
    var wcMax = win.querySelector('.wc--max');
    if (wcMax) {
      wcMax.classList.toggle('is-restore', S.win === 'max');
      var label = S.win === 'max' ? '还原' : '最大化';
      wcMax.setAttribute('title', label);
      wcMax.setAttribute('aria-label', label);
    }
    win.setAttribute('data-app-theme', appThemeEffective());
    win.setAttribute('data-app-theme-pref', S.appTheme);
    ensureReopen().hidden = S.win !== 'closed';
    applySidebarWidth();
    renderRail();
    renderSidebar();
    renderMain();
    renderTree();
    if (flipNeeded) animateWindowFlip(flipFrom);
  }

  function ensureReopen() {
    var el = document.getElementById('winReopen');
    if (el) return el;
    el = document.createElement('button');
    el.id = 'winReopen';
    el.type = 'button';
    el.className = 'win-reopen';
    el.textContent = '窗口已关闭，点此重新打开';
    el.hidden = true;
    win.insertAdjacentElement('afterend', el);
    el.addEventListener('click', function () { S.win = 'normal'; render(); });
    return el;
  }

  /* ============================ 交互 ============================ */

  win.addEventListener('click', function (e) {
    var t = e.target.closest('button');
    if (!t) return;

    if (t.hasAttribute('data-win')) {
      var mode = t.getAttribute('data-win');
      if (mode === 'min') S.win = S.win === 'min' ? 'normal' : 'min';
      else if (mode === 'max') S.win = S.win === 'max' ? 'normal' : 'max';
      else if (mode === 'close') S.win = 'closed';
      render();
      return;
    }
    if (t.hasAttribute('data-page')) {
      var p = t.getAttribute('data-page');
      if (p === 'theme') { cycleTheme(); return; }
      S.page = p;
      S.menuOpen = false;
      render();
      return;
    }
    if (t.hasAttribute('data-tab')) {
      // 切页只换列表，不动当前助手、当前会话与搜索词（真机同为两个 TabBarView 页）
      S.tab = t.getAttribute('data-tab');
      S.menuOpen = false;
      render();
      return;
    }
    if (t.hasAttribute('data-branch')) {
      var d = Number(t.getAttribute('data-branch'));
      S.branch = Math.max(0, Math.min(CHAT.branches.length - 1, S.branch + d));
      S.menuOpen = false;
      render();
      return;
    }
    if (t.hasAttribute('data-branch2')) {
      var d2 = Number(t.getAttribute('data-branch2'));
      S.branch2 = Math.max(0, Math.min(CHAT.followUp.branches.length - 1, S.branch2 + d2));
      S.menuOpen = false;
      render();
      return;
    }
    if (t.hasAttribute('data-menu')) {
      var ml = Number(t.getAttribute('data-menu')) || 1;
      if (S.menuOpen && S.menuLevel === ml) {
        S.menuOpen = false;
      } else {
        S.menuOpen = true;
        S.menuLevel = ml;
      }
      render();
      return;
    }
    if (t.hasAttribute('data-regen')) {
      addBranch(
        Number(t.getAttribute('data-regen')) || 1,
        '重新生成',
        '（演示版）这是一条新的重新生成分支。真实应用会重新调用模型生成新分支，原分支不会被覆盖。'
      );
      return;
    }
    if (t.hasAttribute('data-act')) {
      doAction(t.getAttribute('data-act'), S.menuLevel);
      return;
    }
    if (t.closest && t.closest('[data-think]')) {
      S.thinkOpen = !S.thinkOpen;
      render();
      return;
    }
    if (t.hasAttribute('data-sort')) {
      // 真机这个按钮打开"搜索历史"。模拟里没有历史数据，只给按下反馈，
      // 不再隐式改变列表顺序（见 plans 文档 3.12 的"已知简化"）。
      S.sort = false;
      renderSidebar();
      return;
    }
    if (t.hasAttribute('data-lead')) {
      // 侧栏展开/收起。render() 会重建侧栏 DOM，新元素没有"变化前"的样式，
      // CSS 过渡永远不会触发，所以用 Web Animations API 自己给首尾关键帧。
      // 时长与曲线取自真机 home_desktop_layout.dart：
      // _sidebarAnimDuration = 260ms、_sidebarAnimCurve = Curves.easeOutCubic。
      var sbBefore = document.querySelector('.sbar');
      var widthFrom = sbBefore ? sbBefore.getBoundingClientRect().width : 0;
      S.sidebarOpen = !S.sidebarOpen;
      render();
      var sbAfter = document.querySelector('.sbar');
      if (sbAfter && typeof sbAfter.animate === 'function') {
        var widthTo = S.sidebarOpen ? sbAfter.getBoundingClientRect().width : 0;
        sbAfter.animate(
          [{ width: widthFrom + 'px' }, { width: widthTo + 'px' }],
          { duration: 260, easing: 'cubic-bezier(.215,.61,.355,1)' }
        );
      }
      return;
    }
    if (t.hasAttribute('data-new')) {
      S.hideCanned = true;
      S.appended = [];
      S.note = '';
      S.menuOpen = false;
      render();
      return;
    }
    if (t.hasAttribute('data-chip')) {
      S.note = '演示版：这里会打开模型选择器。';
      render();
      return;
    }
    if (t.hasAttribute('data-scroll')) {
      var st = document.getElementById('cstream');
      if (st) st.scrollTop = t.getAttribute('data-scroll') === 'up' ? 0 : st.scrollHeight;
      return;
    }
    if (t.hasAttribute('data-cmore')) {
      S.composerMenu = S.composerMenu === 'more' ? null : 'more';
      render();
      return;
    }
    if (t.hasAttribute('data-caction')) {
      var a = null;
      for (var i = 0; i < COMPOSER_ACTIONS.length; i++) {
        if (COMPOSER_ACTIONS[i][0] === t.getAttribute('data-caction')) a = COMPOSER_ACTIONS[i];
      }
      var key = t.getAttribute('data-caction');
      if (key === 'ring') {
        S.composerMenu = null;
        S.note = '演示版：这里会打开上下文用量面板。';
      } else if (a && a[3] === 'toggle') {
        S.tools[key] = !S.tools[key];
        S.note = '';
      } else {
        S.composerMenu = S.composerMenu === key ? null : key;
      }
      render();
      return;
    }
    if (t.hasAttribute('data-send')) {
      send();
      return;
    }
    if (t.classList.contains('cchat__edit')) {
      S.editingTitle = true;
      render();
      var ti = document.getElementById('titleInput');
      if (ti) { ti.focus(); ti.select(); }
      return;
    }
  });

  win.addEventListener('dblclick', function (e) {
    if (e.target.closest && e.target.closest('.cchat__name')) {
      S.editingTitle = true;
      render();
      var ti = document.getElementById('titleInput');
      if (ti) { ti.focus(); ti.select(); }
    }
  });

  function addBranch(level, tag, text) {
    var list = levelBranches(level);
    list.push({ tag: tag, think: '', thinkSub: '', text: text });
    setLevelIndex(level, list.length - 1);
    S.menuOpen = false;
    S.note = '';
    render();
  }

  function doAction(act, level) {
    S.menuOpen = false;
    S.note = '';
    var list = levelBranches(level);
    var idx = levelIndex(level);
    if (act === 'fork') { addBranch(level, '分支 · 演示', '（演示版）从这条消息新开了一条分支。真实应用会保留原分支，并在新分支里继续。'); return; }
    if (act === 'del-branch' || act === 'del-node') {
      if (list.length > 1) {
        list.splice(idx, 1);
        setLevelIndex(level, Math.min(idx, list.length - 1));
      } else {
        S.note = '只剩一条分支，不能删除。';
      }
      render();
      return;
    }
    if (act === 'del-all') {
      var keep = list[idx];
      list.splice(0, list.length, keep);
      setLevelIndex(level, 0);
      render();
      return;
    }
    if (act === 'edit') {
      S.editingTitle = true;
      render();
      var ti = document.getElementById('titleInput');
      if (ti) { ti.focus(); ti.select(); }
      return;
    }
    if (act === 'del-one') { S.note = '演示版：删除单条消息会同时移走它下面的子分支，这里不改动演示数据。'; render(); return; }
    if (act === 'del-after') { S.note = '演示版：删除此消息及后续会一并移走后继节点，这里不改动演示数据。'; render(); return; }
    render();
  }

  win.addEventListener('change', function (e) {
    if (e.target && e.target.id === 'titleInput') {
      var v = e.target.value.trim();
      if (v) curTopic().name = v;
      S.editingTitle = false;
      render();
    }
  });

  /* 侧栏宽度拖拽：与真机一致，6px 拖拽区、范围 200–360、默认 300 */
  var sbHandle = document.getElementById('sbHandle');
  if (sbHandle) {
    var dragX = 0;
    sbHandle.addEventListener('pointerdown', function (e) {
      dragX = e.clientX;
      sbHandle.classList.add('is-dragging');
      if (sbHandle.setPointerCapture) {
        try { sbHandle.setPointerCapture(e.pointerId); } catch (err) {}
      }
      e.preventDefault();
    });
    sbHandle.addEventListener('pointermove', function (e) {
      if (!sbHandle.classList.contains('is-dragging')) return;
      var dx = e.clientX - dragX;
      dragX = e.clientX;
      S.sidebarWidth = Math.max(200, Math.min(360, S.sidebarWidth + dx));
      applySidebarWidth();
    });
    var endDrag = function (e) {
      sbHandle.classList.remove('is-dragging');
      if (e && e.pointerId != null && sbHandle.hasPointerCapture && sbHandle.hasPointerCapture(e.pointerId)) {
        try { sbHandle.releasePointerCapture(e.pointerId); } catch (err) {}
      }
    };
    sbHandle.addEventListener('pointerup', endDrag);
    sbHandle.addEventListener('pointercancel', endDrag);
  }

  function applySidebarWidth() {
    win.style.setProperty('--sbw', S.sidebarWidth + 'px');
  }

  win.addEventListener('keydown', function (e) {
    if (e.target && e.target.id === 'titleInput' && e.key === 'Enter') {
      e.target.blur();
    }
  });

  listEl.addEventListener('click', function (e) {
    var li = e.target.closest('.sbar__item');
    if (!li) return;
    var id = li.getAttribute('data-id');
    if (S.tab === 'assistant') {
      S.assistantId = id;
      S.topicId = curAssistant().topics[0].id;
    } else {
      S.topicId = id;
    }
    S.hideCanned = false;
    S.appended = [];
    S.note = '';
    S.menuOpen = false;
    S.branch = 1;
    S.branch2 = 0;
    S.menuLevel = 1;
    S.editingTitle = false;
    render();
  });

  if (queryEl) {
    queryEl.addEventListener('input', function () {
      S.query = queryEl.value;
      renderSidebar();
    });
  }

  /* 发送按钮的可用状态：真机是「trim 后为空即禁用」——空串、纯空格都算空。 */
  function syncSendState() {
    var btn = document.querySelector('.ctool--send');
    var input = document.getElementById('composerInput');
    if (!btn) return;
    var empty = !input || input.value.trim() === '';
    btn.classList.toggle('is-disabled', empty);
    btn.setAttribute('aria-disabled', empty ? 'true' : 'false');
  }

  function send() {
    var input = document.getElementById('composerInput');
    if (!input) return;
    var text = input.value.trim();
    if (!text) return;
    // 在「新建会话」里真的发送消息后，这个会话要出现在侧栏列表里（真机行为），
    // 名字取首条消息的前若干字。
    if (S.hideCanned) {
      var a = curAssistant();
      if (a) {
        // 真机这里先用默认名「新对话」（chatServiceDefaultConversationTitle），
        // 标题是之后由模型生成的，不是直接截取首条消息
        a.topics.unshift({
          id: 'new-topic-' + Date.now(),
          name: '新对话',
          demo: false,
          q: text,
          a: '（演示版固定回复）收到。这里本应调用模型，演示环境中固定返回一段话。',
        });
        S.topicId = a.topics[0].id;
      }
      S.hideCanned = false;
      // 这条消息由新会话的 q/a 渲染，不再往 appended 里重复推一份
      render();
      syncSendState();
      setTimeout(function () { render(); }, 450);
      return;
    }
    S.appended.push({ role: 'user', text: text });
    input.value = '';
    render();
    syncSendState();
    setTimeout(function () {
      S.appended.push({ role: 'assistant', text: '（演示版固定回复）收到。这里本应调用模型，演示环境中固定返回一段话。' });
      render();
    }, 450);
  }

  /* 主题随图标栏的“主题切换”按钮循环，与页头按钮共用同一个偏好 */
  /* 模拟界面自己的主题过渡：用应用那边的 Flutter 默认时长（200ms 线性）。
     跟随网页时走的是网站自己的 .theme-anim，不需要这条。 */
  function markAppThemeAnim() {
    win.classList.add('app-theme-anim');
    void win.offsetWidth; // 先让过渡规则生效，否则本次变化会被合并成硬切
    if (appThemeAnimTimer) window.clearTimeout(appThemeAnimTimer);
    appThemeAnimTimer = window.setTimeout(function () {
      win.classList.remove('app-theme-anim');
    }, 240);
  }

  /* 只切模拟界面自己的主题；网页主题由页头的按钮单独控制，两者互不干涉。 */
  function cycleTheme() {
    var order = ['page', 'light', 'dark'];
    var next = order[(order.indexOf(S.appTheme) + 1) % order.length];
    if (next !== 'page') markAppThemeAnim();
    S.appTheme = next;
    render();
  }

  document.addEventListener('input', function (e) {
    if (e.target && e.target.id === 'composerInput') syncSendState();
  }, true);

  render();
})();
