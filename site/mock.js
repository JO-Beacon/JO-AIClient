/* JO-AIClient 官网 —— 首屏“Windows 桌面版”交互模拟器
   纯前端内存状态，不连任何后台；每个按钮都是真实状态变更。 */

(function () {
  'use strict';

  var win = document.getElementById('win');
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
       300 会把会话区挤得很窄，所以这里取应用字段默认值 240。
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
    tools: {}
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
  var ICON_LIST = '<svg width="16" height="13" viewBox="0 0 20 16" fill="currentColor" aria-hidden="true"><rect x="0" y="2.4" width="20" height="2.2" rx="1.1"/><rect x="0" y="11.4" width="13" height="2.2" rx="1.1"/></svg>';
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
    rail.querySelector('.rail__avatar').textContent = 'J';
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
    var sortBtn = document.querySelector('.sbar__sort');
    if (sortBtn) {
      sortBtn.classList.toggle('is-on', S.sort);
      sortBtn.title = S.sort ? '按默认顺序' : '按名称排序';
    }
    listEl.innerHTML = rows.length
      ? rows.map(function (x) {
          return '<li class="sbar__item' + (x.id === selected ? ' is-on' : '') + '" data-id="' + x.id + '" data-name="' + esc(x.name) + '">' +
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

  function thinkBox(b) {
    if (!b.think) return '';
    var lines = b.thinkSub ? b.thinkSub.split(' · ') : [];
    return '<div class="cthink"><div class="cthink__h">' + esc(b.think) + '</div>' +
      (lines.length
        ? '<ul class="cthink__l">' + lines.map(function (l) { return '<li>' + esc(l) + '</li>'; }).join('') + '</ul>'
        : '') +
      '</div>';
  }

  function composerHtml() {
    var toolDefs = [
      ['add', '<span class="lic lic-plus"></span>'],
      ['attach', '<span class="lic lic-paperclip"></span>'],
      ['brain', '<span class="lic lic-brain"></span>'],
      ['image', '<span class="lic lic-image"></span>'],
      ['tools', '<span class="lic lic-tool-case"></span>'],
      ['note', '<span class="lic lic-book-open"></span>'],
      ['link', '<span class="lic lic-link"></span>'],
      ['tag', '<span class="lic lic-tag"></span>']
    ];
    return '<div class="composer">' +
      '<input class="composer__in" id="composerInput" type="text" placeholder="输入消息与AI聊天" autocomplete="off">' +
      '<div class="composer__tools">' +
        toolDefs.map(function (t) {
          return '<button type="button" class="ctool' + (t[0] === 'add' ? ' ctool--add' : '') + (S.tools[t[0]] ? ' is-on' : '') + '" data-tool="' + t[0] + '" title="' + t[0] + '">' + t[1] + '</button>';
        }).join('') +
        '<button type="button" class="ctool ctool--send" data-send="1" title="发送"><span class="lic lic-arrow-up"></span></button>' +
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
        '<button type="button" class="cchat__chip" data-chip="1" title="切换模型"><span class="cchat__chip-ico"></span>' + esc(CHAT.model) + ' <em>|</em> ' + esc(CHAT.provider) + '</button>' +
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
        '<div class="cmsg cmsg--u"><p>' + esc(topic.q) + '</p></div>' +
        '<div class="cmsg cmsg--a"><p>' + esc(topic.a) + '</p></div>';
    }
    streamBody += S.appended.map(function (m) {
      return '<div class="cmsg cmsg--' + (m.role === 'user' ? 'u' : 'a') + '"><p>' + esc(m.text) + '</p></div>';
    }).join('');
    mainEl.innerHTML = head +
      '<div class="cstream" id="cstream">' + streamBody + '</div>' +
      '<div class="cscrollnav">' +
        '<button type="button" class="cscrollnav__b" data-scroll="up" title="回到顶部"><span class="lic lic-chevron-up"></span></button>' +
        '<button type="button" class="cscrollnav__b" data-scroll="down" title="回到最新"><span class="lic lic-chevron-down"></span></button>' +
      '</div>' +
      composerHtml();
    var stream = document.getElementById('cstream');
    if (stream) stream.scrollTop = stream.scrollHeight;
  }

  /* 一条助手消息：思考块 + 正文 + 代码 + 它所在层的分支控件 */
  function branchRow(level, index, count, tag) {
    var attr = level === 2 ? 'data-branch2' : 'data-branch';
    return '<div class="cbranch">' +
      '<button type="button" class="cbranch__b" ' + attr + '="-1"' + (index <= 0 ? ' disabled' : '') + '><span class="lic lic-chevron-left"></span></button>' +
      '<span class="cbranch__l">分支 ' + (index + 1) + ' / ' + count + '</span>' +
      '<button type="button" class="cbranch__b" ' + attr + '="1"' + (index >= count - 1 ? ' disabled' : '') + '><span class="lic lic-chevron-right"></span></button>' +
      '<span class="cbranch__tag">' + esc(tag) + '</span>' +
      '<button type="button" class="cbranch__regen" data-regen="' + level + '" title="重新生成"><span class="lic lic-rotate-cw"></span></button>' +
      '<button type="button" class="cbranch__more" data-menu="' + level + '" title="更多操作"><span class="lic lic-ellipsis"></span></button>' +
    '</div>';
  }

  function aiMsg(b, level, index, count) {
    return '<div class="cmsg cmsg--a">' +
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
      '<div class="cmsg cmsg--u"><p>' + esc(CHAT.question) + '</p></div>' +
      aiMsg(CHAT.branches[S.branch], 1, S.branch, CHAT.branches.length);
    if (S.branch === fu.parentIndex) {
      body += '<div class="cmsg cmsg--u"><p>' + esc(fu.question) + '</p></div>' +
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

  function render() {
    // 用 classList 逐个切换，不用整串 className 赋值，
    // 否则会把动画类（app-theme-anim）冲掉。
    win.classList.toggle('is-max', S.win === 'max');
    win.classList.toggle('is-min', S.win === 'min');
    win.classList.toggle('is-closed', S.win === 'closed');
    win.classList.toggle('is-collapsed', !S.sidebarOpen);
    win.setAttribute('data-app-theme', appThemeEffective());
    win.setAttribute('data-app-theme-pref', S.appTheme);
    ensureReopen().hidden = S.win !== 'closed';
    applySidebarWidth();
    renderRail();
    renderSidebar();
    renderMain();
    renderTree();
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
    if (t.hasAttribute('data-sort')) {
      S.sort = !S.sort;
      renderSidebar();
      return;
    }
    if (t.hasAttribute('data-lead')) {
      S.sidebarOpen = !S.sidebarOpen;
      render();
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
    if (t.hasAttribute('data-tool')) {
      var k = t.getAttribute('data-tool');
      S.tools[k] = !S.tools[k];
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

  function send() {
    var input = document.getElementById('composerInput');
    if (!input) return;
    var text = input.value.trim();
    if (!text) return;
    S.appended.push({ role: 'user', text: text });
    input.value = '';
    render();
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

  render();
})();
