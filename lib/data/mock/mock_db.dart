import '../../domain/entities/match_level.dart';
import '../../domain/entities/professor.dart';
import '../../domain/entities/query_understanding.dart';
import '../../domain/entities/recommendation.dart';
import '../../domain/entities/recommendation_result.dart';

/// 内存假数据库：导师 fixtures + 简单关键词匹配，产出像真的推荐结果。
class MockDb {
  MockDb();

  /// 已知研究方向关键词；同义词归一到展示名。
  static const Map<String, String> _interestSynonyms = {
    '人工智能': '人工智能',
    'AI': '人工智能',
    '计算机视觉': '计算机视觉',
    'CV': '计算机视觉',
    '自然语言处理': '自然语言处理',
    'NLP': '自然语言处理',
    '大模型': '大模型',
    '大语言模型': '大语言模型',
    '大模型安全': '大模型安全',
    '人工智能安全': '人工智能安全',
    'AI安全': '人工智能安全',
    'AI系统工程': 'AI系统工程',
    'AI4S': 'AI4S',
    '大模型治理': '大模型治理',
    '大模型安全合规': '大模型安全合规',
    '安全对齐': '安全对齐',
    '智能体安全': '智能体安全',
    '智能体推理': '智能体推理',
    'AI应用安全': 'AI应用安全',
    '系统安全': '系统安全',
    '医学影像': '医学影像',
    '智慧医疗': '智慧医疗',
    '医疗机器人': '医疗机器人',
    '物理仿真': '物理仿真',
    '机器人': '机器人',
    '具身智能': '具身智能',
    'SLAM': 'SLAM',
    '机器学习': '机器学习',
    '机器学习系统': '机器学习系统',
    '图神经网络': '图神经网络',
    '计算机图形学': '计算机图形学',
    '虚拟现实': '虚拟现实',
    '软件工程': '软件工程',
    '软件测试': '软件测试',
    '软件系统': '软件系统',
    '软件安全': '软件安全',
    '软件供应链安全': '软件供应链安全',
    '智能合约安全': '智能合约安全',
    '开源安全': '开源安全',
    '开源软件治理': '开源软件治理',
    '可信软件': '可信软件',
    '形式化方法': '形式化方法',
    '网络安全': '网络安全',
    '信息安全': '信息安全',
    '数据安全': '数据安全',
    '漏洞挖掘': '漏洞挖掘',
    '物联网安全': '物联网安全',
    '应用系统安全': '应用系统安全',
    '密码学': '密码学',
    '格密码': '格密码',
    '全同态加密': '全同态加密',
    '计算机网络': '计算机网络',
    '网络传输协议': '网络传输协议',
    '移动边缘计算': '移动边缘计算',
    '软件定义网络': '软件定义网络',
    '视频传输': '视频传输',
    '智能制造': '智能制造',
    '数字孪生': '数字孪生',
    '大数据': '大数据',
    '机器视觉': '机器视觉',
    '模式识别': '模式识别',
    '可靠感知': '可靠感知',
    '对抗攻击': '对抗攻击',
    '信号处理': '信号处理',
    '集成电路': '集成电路',
    '嵌入式系统': '嵌入式系统',
    '区块链': '区块链',
    '智能计算': '智能计算',
    '高性能计算': '高性能计算',
    '异构计算': '异构计算',
    '云计算': '云计算',
    '数据库': '数据库',
    '隐私计算': '隐私计算',
    '联邦学习': '联邦学习',
    '生物信息': '生物信息',
    '材料计算': '材料计算',
    '深度学习': '深度学习',
    '强化学习': '强化学习',
    '推荐系统': '推荐系统',
    '知识图谱': '知识图谱',
    '自动驾驶': '自动驾驶',
    '多模态': '多模态',
    '多模态大模型': '多模态大模型',
    '生成式模型': '生成式模型',
    '扩散模型': '扩散模型',
    '计算智能': '计算智能',
    '进化计算': '进化计算',
    '物理AI': '物理AI',
    '类脑智能': '类脑智能',
    '图学习': '图学习',
    '图数据挖掘': '图数据挖掘',
    '数据挖掘': '数据挖掘',
    '信息检索': '信息检索',
    '算法设计': '算法设计',
    '数据结构': '数据结构',
    '智能控制': '智能控制',
    '无人系统': '无人系统',
    '群体智能': '群体智能',
    '无人机': '无人机',
    '智能电网': '智能电网',
    '能源互联网': '能源互联网',
    '多智能体': '多智能体',
    '数据中心网络': '数据中心网络',
    '智能物联网': '智能物联网',
    '物联网': '物联网',
    '无线通信': '无线通信',
    '卫星通信': '卫星通信',
    '通感一体化': '通感一体化',
    'AI加速器': 'AI加速器',
    '智能处理器': '智能处理器',
    '智能处理器芯片': '智能处理器芯片',
    '框架工具链': '框架工具链',
    'NPU': 'NPU',
    '图像处理器': '图像处理器',
    'FPGA': 'FPGA',
    '软硬件协同设计': '软硬件协同设计',
    '图计算': '图计算',
    '大模型推理': '大模型推理',
    '时序预测': '时序预测',
    'Web智能信息处理': 'Web智能信息处理',
    '多媒体': '多媒体',
    '量子信息': '量子信息',
    '感存算一体': '感存算一体',
    '智能相机': '智能相机',
    '工业大数据': '工业大数据',
    '故障诊断': '故障诊断',
    '低功耗设计': '低功耗设计',
    '能量采集': '能量采集',
    'AI for Science': 'AI4S',
    '图像处理': '图像处理',
    'EDA': 'AI-based EDA',
    'AI-based EDA': 'AI-based EDA',
  };

  static const List<String> _locationKeywords = [
    '北京',
    '天津',
    '华北',
    '上海',
    '江浙沪',
    '浙江',
    '杭州',
    '江苏',
    '南京',
    '湖北',
    '武汉',
    '华中',
    '广东',
    '深圳',
    '广州',
    '安徽',
    '合肥',
    '陕西',
    '西安',
    '黑龙江',
    '哈尔滨',
    '四川',
    '成都',
    '西南',
    '华东',
  ];

  final List<_Fixture> _fixtures = _buildFixtures();

  List<Professor> get allProfessors =>
      _fixtures.map((f) => f.professor).toList(growable: false);

  Professor? getProfessor(String id) {
    for (final f in _fixtures) {
      if (f.professor.id == id) return f.professor;
    }
    return null;
  }

  RecommendationResult recommend(String prompt, {String? sessionId}) {
    final interests = _detectInterests(prompt);
    final locations = _detectLocations(prompt);
    final degree = _detectDegree(prompt);

    final scored = <_Scored>[];
    for (final f in _fixtures) {
      final matchedFields = f.professor.researchFields
          .where((field) => interests.contains(field))
          .toList();
      final matchedLocs = f.locationTags
          .where((loc) => locations.contains(loc))
          .toList();
      final score = matchedFields.length * 2 + matchedLocs.length;
      if (score <= 0) continue;
      scored.add(_Scored(f, score, matchedFields));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));

    final maxScore = scored.isEmpty ? 1 : scored.first.score;
    final recommendations = scored.map((s) {
      final normScore = (s.score / (maxScore == 0 ? 1 : maxScore)).clamp(
        0.0,
        1.0,
      );
      return Recommendation(
        professorId: s.fixture.professor.id,
        name: s.fixture.professor.name,
        university: s.fixture.professor.university,
        college: s.fixture.professor.college,
        title: s.fixture.professor.title,
        researchFields: s.fixture.professor.researchFields,
        homepageUrl: s.fixture.professor.homepageUrl,
        matchLevel: _levelFor(s.score),
        matchScore: double.parse(normScore.toStringAsFixed(2)),
        reason: _buildReason(s.matchedFields, locations),
        limitations: s.fixture.limitations,
      );
    }).toList();

    return RecommendationResult(
      sessionId: sessionId ?? 's_${prompt.hashCode.toUnsigned(20)}',
      queryUnderstanding: QueryUnderstanding(
        researchInterests: interests,
        preferredLocations: locations,
        preferredUniversities: const [],
        degreeStage: degree,
        uncertainties: _buildUncertainties(prompt, degree),
      ),
      recommendations: recommendations,
      followUpQuestions: const ['偏理论', '偏应用', '只看985', '适合硕士'],
    );
  }

  List<String> _detectInterests(String prompt) {
    final found = <String>{};
    _interestSynonyms.forEach((kw, canonical) {
      if (prompt.contains(kw)) found.add(canonical);
    });
    return found.toList();
  }

  List<String> _detectLocations(String prompt) =>
      _locationKeywords.where(prompt.contains).toSet().toList();

  String? _detectDegree(String prompt) {
    if (prompt.contains('博士') ||
        prompt.contains('申博') ||
        prompt.contains('读博')) {
      return '博士';
    }
    if (prompt.contains('硕士') ||
        prompt.contains('保研') ||
        prompt.contains('考研') ||
        prompt.contains('读研')) {
      return '硕士';
    }
    return null;
  }

  MatchLevel _levelFor(int score) {
    if (score >= 4) return MatchLevel.high;
    if (score >= 2) return MatchLevel.medium;
    return MatchLevel.low;
  }

  String _buildReason(List<String> matchedFields, List<String> locations) {
    final fieldPart = matchedFields.isEmpty
        ? '其公开研究方向与你的需求相关'
        : '公开资料显示其研究方向涵盖${matchedFields.join('、')}，与你的需求高度相关';
    final locPart = locations.isEmpty
        ? ''
        : '；且所在地区匹配你的偏好（${locations.join('、')}）';
    return '$fieldPart$locPart。';
  }

  List<String> _buildUncertainties(String prompt, String? degree) {
    final items = <String>[];
    if (degree == null) items.add('未明确申请硕士还是博士');
    if (!prompt.contains('理论') && !prompt.contains('应用')) {
      items.add('未明确偏理论或应用');
    }
    return items;
  }

  static List<_Fixture> _buildFixtures() => const [
    _Fixture(
      professor: Professor(
        id: 'p_001',
        name: '范登平',
        university: '南开大学',
        college: '密码与网络空间安全学院',
        title: '教授',
        researchFields: ['人工智能', '计算机视觉', '医学影像', '多模态'],
        bio:
            '南开大学教授、博导，计算机科学与技术系主任，天津市视觉计算与智能感知重点实验室副主任，入选国家级青年人才。主要研究计算机视觉、多模态学习和医学图像分析，相关成果发表于 CVPR、ICCV、TPAMI 等会议期刊。',
        homepageUrl:
            'https://cyber.nankai.edu.cn/2021/0323/c13838a552011/page.htm',
        sourceUrl:
            'https://cyber.nankai.edu.cn/2021/0323/c13838a552011/page.htm',
        updatedAt: '2026-06-18',
        dataQualityScore: 0.95,
      ),
      locationTags: ['天津', '华北'],
      limitations: ['招生信息以学校主页最新说明为准'],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_002',
        name: '周宇',
        university: '南开大学',
        college: '密码与网络空间安全学院',
        title: '教授',
        researchFields: ['计算机视觉', '多模态大模型', '大模型', '具身智能', '自然语言处理'],
        bio:
            '南开大学计算机/密网学院教授、博导，研究计算机视觉、多模态人工智能、具身智能、自然语言处理和大模型。公开资料显示其聚焦可视文本处理、多模态大模型和智能体，在 CVPR、ICCV、NeurIPS、ICML、ICLR 等会议期刊发表论文。',
        homepageUrl:
            'https://cyber.nankai.edu.cn/2021/0323/c13838a551952/page.htm',
        sourceUrl:
            'https://cyber.nankai.edu.cn/2021/0323/c13838a551952/page.htm',
        updatedAt: '2026-06-18',
        dataQualityScore: 0.94,
      ),
      locationTags: ['天津', '华北'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_003',
        name: '张军',
        university: '南开大学',
        college: '人工智能学院',
        title: '杰出教授',
        researchFields: ['人工智能', '计算智能', '进化计算', '深度学习'],
        bio:
            '南开大学人工智能学院杰出教授，在人工智能基础理论、计算智能、进化计算和创新应用方向有长期积累。公开资料显示其发表高水平论文 500 余篇，Google 学术引用量 27000 余次，曾获国家杰青并入选 IEEE Fellow、中国人工智能学会 Fellow。',
        homepageUrl: 'https://ai.nankai.edu.cn/info/1198/5669.htm',
        sourceUrl: 'https://ai.nankai.edu.cn/info/1198/5669.htm',
        updatedAt: '2026-06-18',
        dataQualityScore: 0.96,
      ),
      locationTags: ['天津', '华北'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_004',
        name: '汪定',
        university: '南开大学',
        college: '密码与网络空间安全学院',
        title: '教授',
        researchFields: ['密码学', '网络安全', '人工智能安全', '数据安全'],
        bio:
            '南开大学教授、博士/硕士生导师，计算机学院副院长、密码与网络空间安全学院副院长。研究公钥密码学、数字身份安全与人工智能安全，主持国家重点研发计划课题、国家自然科学基金等项目，在 IEEE S&P、ACM CCS、USENIX Security、NDSS 等发表论文。',
        homepageUrl:
            'https://cyber.nankai.edu.cn/2021/0323/c13838a551989/page.htm',
        sourceUrl:
            'https://cyber.nankai.edu.cn/2021/0323/c13838a551989/page.htm',
        updatedAt: '2026-06-18',
        dataQualityScore: 0.93,
      ),
      locationTags: ['天津', '华北'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_005',
        name: '张莹',
        university: '南开大学',
        college: '计算机学院',
        title: '教授',
        researchFields: ['自然语言处理', '知识图谱', '数据挖掘', '大模型', '机器学习'],
        bio:
            '南开大学教授、博导，计算机学院、密码与网络空间安全学院副院长，国家级青年人才。主要研究跨媒体分析推理、知识图谱与大模型、自然语言处理和数据挖掘，在 IEEE TIP、IEEE TKDE、NeurIPS、SIGIR、ACL、KDD 等发表论文。',
        homepageUrl:
            'https://cc.nankai.edu.cn/2021/0323/c37280a575886/page.htm',
        sourceUrl: 'https://cc.nankai.edu.cn/2021/0323/c37280a575886/page.htm',
        updatedAt: '2026-06-18',
        dataQualityScore: 0.92,
      ),
      locationTags: ['天津', '华北'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_006',
        name: '任博',
        university: '南开大学',
        college: '计算机学院',
        title: '教授',
        researchFields: ['计算机图形学', '计算机视觉', '人工智能', '具身智能'],
        bio:
            '南开大学计算机学院教授，研究计算机图形学、计算机视觉和具身智能，关注流体模拟、三维场景重建与内容生成。公开资料显示其指导学生在 ACM TOG、SIGGRAPH、TVCG、TIP、CVPR、ICCV 等期刊会议发表论文。',
        homepageUrl:
            'https://cc.nankai.edu.cn/2021/0323/c37281a575896/page.htm',
        sourceUrl: 'https://cc.nankai.edu.cn/2021/0323/c37281a575896/page.htm',
        updatedAt: '2026-06-18',
        dataQualityScore: 0.91,
      ),
      locationTags: ['天津', '华北'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_007',
        name: '戈维峰',
        university: '复旦大学',
        college: '计算与智能创新学院',
        title: '副教授',
        researchFields: ['计算机视觉', '模式识别', '机器学习', '多模态', '机器人'],
        bio:
            '复旦大学计算与智能创新学院副教授，研究计算机视觉、认知计算和人形机器人通用智能，关注视觉感知理解、知识快速学习与多模态认知推理。公开资料显示其在 TIP、TOG、TMM、CVPR、ICCV、ECCV、NeurIPS、AAAI、ACM MM、ACL 等发表论文。',
        homepageUrl: 'http://ai.fudan.edu.cn/gwf/list.htm',
        sourceUrl: 'http://ai.fudan.edu.cn/gwf/list.htm',
        updatedAt: '2026-06-17',
        dataQualityScore: 0.92,
      ),
      locationTags: ['上海', '江浙沪', '华东'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_008',
        name: '周扬帆',
        university: '复旦大学',
        college: '计算与智能创新学院',
        title: '教授',
        researchFields: ['软件系统', '软件工程', '云计算', '智能计算'],
        bio:
            '复旦大学计算与智能创新学院教授、博导，长期从事软件系统研究。公开资料显示其主持和参与多项国家自然科学基金、973 和重点研发项目，近年在 OSDI、SOSP、FSE、ICSE、CSCW 等顶级出版物发表论文，成果在腾讯、华为、美团等企业落地。',
        homepageUrl: 'http://ai.fudan.edu.cn/zyf/list.htm',
        sourceUrl: 'http://ai.fudan.edu.cn/zyf/list.htm',
        updatedAt: '2026-06-17',
        dataQualityScore: 0.94,
      ),
      locationTags: ['上海', '江浙沪', '华东'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_009',
        name: '薛向阳',
        university: '复旦大学',
        college: '计算与智能创新学院',
        title: '教授',
        researchFields: ['多模态大模型', '大模型', '具身智能', '类脑智能', '计算机视觉'],
        bio:
            '复旦大学计算与智能创新学院教授、博士生导师，大数据研究院、类脑智能科学与技术研究院相关负责人。当前研究多模态大模型、具身智能和类脑智能，公开资料显示其在 TPAMI、CVPR、ICCV、NeurIPS 等发表论文 130 余篇，获得国家级和省部级科技奖励。',
        homepageUrl: 'http://ai.fudan.edu.cn/xxy/list.htm',
        sourceUrl: 'http://ai.fudan.edu.cn/xxy/list.htm',
        updatedAt: '2026-06-17',
        dataQualityScore: 0.96,
      ),
      locationTags: ['上海', '江浙沪', '华东'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_010',
        name: '张源',
        university: '复旦大学',
        college: '计算与智能创新学院',
        title: '教授',
        researchFields: ['软件安全', '网络安全', '信息安全', 'AI系统工程'],
        bio:
            '复旦大学计算与智能创新学院教授，国家级青年人才，主要研究软件安全。公开资料显示其研究工作获 USENIX Security、ACM SIGSOFT、IEEE S&P、ACM CCS 等杰出论文奖，部分成果应用于华为、阿里、OPPO、vivo 等公司。',
        homepageUrl: 'http://ai.fudan.edu.cn/zy_37542/list.htm',
        sourceUrl: 'http://ai.fudan.edu.cn/zy_37542/list.htm',
        updatedAt: '2026-06-17',
        dataQualityScore: 0.95,
      ),
      locationTags: ['上海', '江浙沪', '华东'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_011',
        name: '张奇',
        university: '复旦大学',
        college: '计算与智能创新学院',
        title: '教授',
        researchFields: ['自然语言处理', '信息检索', '大模型', '数据密集型计算'],
        bio:
            '复旦大学计算与智能创新学院教授、国家级领军人才、博士生导师，兼任上海市智能信息处理重点实验室副主任等职务。研究自然语言处理、信息检索和数据密集型计算，曾多次担任 ACL、EMNLP、COLING 等会议程序委员会主席或领域主席。',
        homepageUrl: 'http://ai.fudan.edu.cn/zq_40317/list.htm',
        sourceUrl: 'http://ai.fudan.edu.cn/zq_40317/list.htm',
        updatedAt: '2026-06-17',
        dataQualityScore: 0.94,
      ),
      locationTags: ['上海', '江浙沪', '华东'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_012',
        name: '章忠志',
        university: '复旦大学',
        college: '计算与智能创新学院',
        title: '教授',
        researchFields: ['图学习', '图数据挖掘', '数据挖掘', '网络科学'],
        bio:
            '复旦大学计算与智能创新学院教授、博士生导师，研究图学习理论与算法、图数据挖掘、社交网络分析和网络科学。公开资料显示其在 TIT、TKDE、TIFS、SODA、SIGMOD、KDD、NeurIPS、WWW、ICDE、IJCAI、AAAI 等发表论文 200 余篇。',
        homepageUrl: 'http://ai.fudan.edu.cn/zzz/list.htm',
        sourceUrl: 'http://ai.fudan.edu.cn/zzz/list.htm',
        updatedAt: '2026-06-17',
        dataQualityScore: 0.93,
      ),
      locationTags: ['上海', '江浙沪', '华东'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_013',
        name: '陶俊',
        university: '复旦大学',
        college: '微电子学院',
        title: '教授',
        researchFields: ['AI-based EDA', 'AI加速器', '集成电路', '芯粒集成'],
        bio:
            '复旦大学微电子学院教授，IEEE 高级会员，研究 AI-based EDA、AI 加速算法与 AI 加速器设计优化、混合信号系统建模与优化、芯粒集成系统自动化设计。公开资料显示其在 TCAD、TCAS、DAC、ICCAD、DATE 等发表论文近百篇。',
        homepageUrl: 'https://sme.fudan.edu.cn/60/2b/c31154a352299/page.htm',
        sourceUrl: 'https://sme.fudan.edu.cn/60/2b/c31154a352299/page.htm',
        updatedAt: '2026-06-16',
        dataQualityScore: 0.91,
      ),
      locationTags: ['上海', '江浙沪', '华东'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_014',
        name: '黄剑',
        university: '华中科技大学',
        college: '人工智能与自动化学院',
        title: '教授',
        researchFields: ['机器人', '智能控制', '生物信息', '人工智能'],
        bio:
            '华中科技大学二级教授、博士生导师，人工智能与自动化学院智能科学与技术系主任，类脑智能系统湖北省重点实验室主任，入选国家万人计划科技创新领军人才。研究智能机器人、生物信息学、网络化控制、智能控制和人机电一体化系统。',
        homepageUrl: 'http://faculty.hust.edu.cn/huangjian2/zh_CN/index.htm',
        sourceUrl: 'http://faculty.hust.edu.cn/huangjian2/zh_CN/index.htm',
        updatedAt: '2026-06-30',
        dataQualityScore: 0.95,
      ),
      locationTags: ['湖北', '武汉', '华中'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_015',
        name: '徐鹏',
        university: '华中科技大学',
        college: '网络空间安全学院',
        title: '教授',
        researchFields: ['密码学', '数据安全', '格密码', '全同态加密', '网络安全'],
        bio:
            '华中科技大学网络空间安全学院教授、博导，研究密码学、数据安全、格密码、可搜索加密和全同态加密。公开资料显示其论文发表于 CCS、USENIX Security、NDSS、DAC、ESORICS、PKC、IEEE TC、IEEE TIFS、IEEE TDSC 等。',
        homepageUrl: 'http://faculty.hust.edu.cn/xupeng1/zh_CN/index.htm',
        sourceUrl: 'http://faculty.hust.edu.cn/xupeng1/zh_CN/index.htm',
        updatedAt: '2026-06-30',
        dataQualityScore: 0.94,
      ),
      locationTags: ['湖北', '武汉', '华中'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_016',
        name: '尤新革',
        university: '华中科技大学',
        college: '网络空间安全学院',
        title: '二级教授',
        researchFields: ['模式识别', '计算机视觉', '机器学习', '数据挖掘', '生物特征识别'],
        bio:
            '华中科技大学网络空间安全学院二级教授、博士生导师，IET Fellow，研究模式识别、图像与信号处理、计算机视觉、机器学习与数据挖掘、生物特征识别与智能防伪，担任多个 IEEE/IET 相关期刊编委或客座主编。',
        homepageUrl: 'http://bmal.hust.edu.cn/info/1005/1091.htm',
        sourceUrl: 'http://bmal.hust.edu.cn/info/1005/1091.htm',
        updatedAt: '2026-06-30',
        dataQualityScore: 0.93,
      ),
      locationTags: ['湖北', '武汉', '华中'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_017',
        name: '陆昊',
        university: '华中科技大学',
        college: '人工智能与自动化学院',
        title: '副教授',
        researchFields: ['计算机视觉', '语义分割', '图像抠图', '深度学习'],
        bio:
            '华中科技大学人工智能与自动化学院副教授、博导，研究计算机视觉、稠密预测、图像抠图、目标计数与语义分割。公开资料显示其在 TPAMI、IJCV、CVPR、ICCV、ECCV、NeurIPS、AAAI、ACM MM 等视觉领域期刊会议发表论文。',
        homepageUrl: 'http://faculty.hust.edu.cn/hlu/zh_CN/index.htm',
        sourceUrl: 'http://faculty.hust.edu.cn/hlu/zh_CN/index.htm',
        updatedAt: '2026-06-30',
        dataQualityScore: 0.91,
      ),
      locationTags: ['湖北', '武汉', '华中'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_018',
        name: '胡涛',
        university: '华中科技大学',
        college: '软件学院',
        title: '教授',
        researchFields: ['生成式模型', '扩散模型', '多模态', '计算机视觉', '人工智能'],
        bio:
            '华中科技大学软件学院教授，入选国家级高层次青年人才计划，研究生成式模型、扩散模型、流匹配、多模态学习、高效视觉表征学习和计算机视觉。公开资料显示其以第一作者或共同第一作者在 CVPR、ICCV、ECCV、AAAI 等发表论文。',
        homepageUrl: 'https://sse.hust.edu.cn/info/1172/4605.htm',
        sourceUrl: 'https://sse.hust.edu.cn/info/1172/4605.htm',
        updatedAt: '2026-06-30',
        dataQualityScore: 0.91,
      ),
      locationTags: ['湖北', '武汉', '华中'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_019',
        name: '盛银',
        university: '华中科技大学',
        college: '人工智能与自动化学院',
        title: '副教授',
        researchFields: ['无人系统', '强化学习', '智能控制', '机器人'],
        bio:
            '华中科技大学人工智能与自动化学院副教授、博士生导师、硕士生导师，研究自主无人系统、强化学习和智能控制。公开资料显示其发表 SCI 期刊论文 40 余篇，其中 IEEE 汇刊论文 20 余篇，入选国家博士后创新人才支持计划。',
        homepageUrl: 'http://faculty.hust.edu.cn/ShengYin/zh_CN/index.htm',
        sourceUrl: 'http://faculty.hust.edu.cn/ShengYin/zh_CN/index.htm',
        updatedAt: '2026-06-30',
        dataQualityScore: 0.89,
      ),
      locationTags: ['湖北', '武汉', '华中'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_020',
        name: '牛建伟',
        university: '北京航空航天大学',
        college: '计算机学院',
        title: '教授',
        researchFields: ['具身智能', '机器人', '机器学习', '嵌入式系统'],
        bio:
            '北航蓝天杰出二级教授、博士生导师，IEEE Fellow，任北航具身智能机器人研究院副院长。主要从事具身智能、机器人操作系统、机器学习与智能嵌入式系统研究，主持多项国家重点研发计划和自然科学基金项目，相关工业机器人操作系统成果已在企业应用。',
        homepageUrl: 'https://scse.buaa.edu.cn/info/1078/2664.htm',
        sourceUrl: 'https://scse.buaa.edu.cn/info/1078/2664.htm',
        updatedAt: '2026-06-04',
        dataQualityScore: 0.95,
      ),
      locationTags: ['北京', '华北'],
      limitations: ['招生信息以学校主页最新说明为准'],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_021',
        name: '邱望洁',
        university: '北京航空航天大学',
        college: '人工智能学院',
        title: '副教授',
        researchFields: ['信息安全', '区块链', '隐私计算', '网络安全'],
        bio:
            '北航人工智能研究院未来区块链与隐私计算高精尖创新中心副研究员、博士生导师。研究信息安全、区块链、隐私计算及交叉应用，发表多篇高水平论文并申请多项发明专利，参与长安链、雄安链等区块链系统研发与应用。',
        homepageUrl: 'https://iai.buaa.edu.cn/info/1013/2685.htm',
        sourceUrl: 'https://iai.buaa.edu.cn/info/1013/2685.htm',
        updatedAt: '2026-06-04',
        dataQualityScore: 0.89,
      ),
      locationTags: ['北京', '华北'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_022',
        name: '白跃彬',
        university: '北京航空航天大学',
        college: '计算机学院',
        title: '教授',
        researchFields: ['智能计算', '嵌入式系统', '大模型', '云计算'],
        bio:
            '北航计算机学院教授、博士生导师，长期带领分布式系统与网络研究组开展智能计算系统、云操作系统性能优化、实时嵌入式操作系统等研究。主持完成多项国家自然科学基金、863 和预研项目，近期关注 AI 加速器结构及大模型训推相关智能计算系统。',
        homepageUrl: 'https://scse.buaa.edu.cn/info/1078/2662.htm',
        sourceUrl: 'https://scse.buaa.edu.cn/info/1078/2662.htm',
        updatedAt: '2026-06-04',
        dataQualityScore: 0.9,
      ),
      locationTags: ['北京', '华北'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_023',
        name: '郎波',
        university: '北京航空航天大学',
        college: '计算机学院',
        title: '教授',
        researchFields: ['机器学习', '信息安全', '深度学习', '图神经网络'],
        bio:
            '北航计算机学院教授、博士生导师，研究基于机器学习的大数据分析与管理、信息安全、可解释深度学习和图神经网络。主持多项自然科学基金、863 计划和重大专项课题，在 CVPR、AAAI 等会议及 SCI 期刊发表多篇论文。',
        homepageUrl: 'https://scse.buaa.edu.cn/info/1078/2660.htm',
        sourceUrl: 'https://scse.buaa.edu.cn/info/1078/2660.htm',
        updatedAt: '2026-06-04',
        dataQualityScore: 0.9,
      ),
      locationTags: ['北京', '华北'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_024',
        name: '汪淼',
        university: '北京航空航天大学',
        college: '计算机学院',
        title: '教授',
        researchFields: ['计算机图形学', '虚拟现实', '多模态'],
        bio:
            '北航计算机学院教授、博士生导师，国家级青年人才，依托虚拟现实技术与系统全国重点实验室开展计算机图形学、虚拟现实和增强现实研究。主持国家自然科学基金和校企合作项目，在 ACM TOG、IEEE TVCG、IEEE VR 等期刊会议发表论文。',
        homepageUrl: 'http://miaowang.me',
        sourceUrl: 'https://scse.buaa.edu.cn/info/1078/11962.htm',
        updatedAt: '2026-06-04',
        dataQualityScore: 0.92,
      ),
      locationTags: ['北京', '华北'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_025',
        name: '张辉',
        university: '北京航空航天大学',
        college: '计算机学院',
        title: '教授',
        researchFields: ['网络安全', '数据安全', '人工智能', '计算机网络'],
        bio:
            '北航计算机学院教授、博士生导师，主讲计算机网络课程，研究计算机网络、数据安全和基于 AI 的网络安全。牵头承担国家 973、863、重点研发计划等项目，参与多项数据汇聚、管理、质量和服务相关国家标准工作。',
        homepageUrl: 'https://scse.buaa.edu.cn/info/1078/2677.htm',
        sourceUrl: 'https://scse.buaa.edu.cn/info/1078/2677.htm',
        updatedAt: '2026-06-04',
        dataQualityScore: 0.88,
      ),
      locationTags: ['北京', '华北'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_026',
        name: '王莉莉',
        university: '北京航空航天大学',
        college: '计算机学院',
        title: '教授',
        researchFields: ['虚拟现实', '计算机图形学', '多模态'],
        bio:
            '北航计算机学院教授、博士生导师，虚拟现实技术与系统全国重点实验室副主任，中国计算机学会虚拟现实与可视化专委会副主任。研究虚拟现实、混合现实和计算机图形学，主持自然科学基金重大项目课题和重点研发计划课题。',
        homepageUrl: 'https://scse.buaa.edu.cn/info/1078/2672.htm',
        sourceUrl: 'https://scse.buaa.edu.cn/info/1078/2672.htm',
        updatedAt: '2026-06-04',
        dataQualityScore: 0.93,
      ),
      locationTags: ['北京', '华北'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_027',
        name: '刘庆杰',
        university: '北京航空航天大学',
        college: '计算机学院',
        title: '教授',
        researchFields: ['计算机视觉', '多模态大模型', '大模型', '深度学习'],
        bio:
            '北航计算机学院教授、博士生导师，主要研究计算机视觉、目标检测、视频跟踪与多模态大模型。曾获图象图形学会技术发明一等奖，指导团队在 ICDAR、ICCV VOT 等竞赛中取得成绩，在 NeurIPS、CVPR、ICML、ICCV 等会议发表论文。',
        homepageUrl: 'https://scse.buaa.edu.cn/info/1078/11957.htm',
        sourceUrl: 'https://scse.buaa.edu.cn/info/1078/11957.htm',
        updatedAt: '2026-06-05',
        dataQualityScore: 0.93,
      ),
      locationTags: ['北京', '华北'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_028',
        name: '杨海龙',
        university: '北京航空航天大学',
        college: '计算机学院',
        title: '教授',
        researchFields: ['深度学习', '大模型', '高性能计算', '智能计算'],
        bio:
            '北航计算机学院教授、博士生导师，研究深度学习编译优化、大模型训推系统、高性能计算和稀疏数值算法。主持国家重点研发计划和国家自然科学基金项目，在 SC、ISCA、ASPLOS、PLDI、ICSE 等会议期刊发表论文并指导超算竞赛团队。',
        homepageUrl: 'https://thomas-yang.github.io',
        sourceUrl: 'https://scse.buaa.edu.cn/info/1546/10606.htm',
        updatedAt: '2026-06-04',
        dataQualityScore: 0.92,
      ),
      locationTags: ['北京', '华北'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_029',
        name: '盛律',
        university: '北京航空航天大学',
        college: '软件学院',
        title: '教授',
        researchFields: ['具身智能', '三维视觉', '多模态大模型', '大模型'],
        bio:
            '北京航空航天大学软件学院教授、博士研究生导师，北航软件学院智能软件工程所副所长，入选国家级青年人才、智源学者和小米青年学者。研究具身智能、三维视觉和多模态大模型，在 TPAMI、IJCV、CVPR、ICCV、NeurIPS、ICLR、ECCV 等发表论文。',
        homepageUrl:
            'https://soft.buaa.edu.cn/teachershouw.jsp?urltype=news.NewsContentUrl&wbtreeid=1337&wbnewsid=12007',
        sourceUrl:
            'https://soft.buaa.edu.cn/teachershouw.jsp?urltype=news.NewsContentUrl&wbtreeid=1337&wbnewsid=12007',
        updatedAt: '2026-06-04',
        dataQualityScore: 0.94,
      ),
      locationTags: ['北京', '华北'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_030',
        name: '陶飞',
        university: '北京航空航天大学',
        college: '软件学院',
        title: '教授',
        researchFields: ['数字孪生', '智能制造', '云计算', '大数据'],
        bio:
            '北航软件学院教授、博导，国家级人才，长期从事数字孪生、数字工程、智能制造和制造工业软件研究。公开资料显示其出版多部专著，在 Nature 等期刊发表高被引论文，连续多年入选全球高被引学者和 Elsevier 中国高被引学者。',
        homepageUrl:
            'https://soft.buaa.edu.cn/teachershouw.jsp?urltype=news.NewsContentUrl&wbtreeid=1337&wbnewsid=12053',
        sourceUrl:
            'https://soft.buaa.edu.cn/teachershouw.jsp?urltype=news.NewsContentUrl&wbtreeid=1337&wbnewsid=12053',
        updatedAt: '2026-06-04',
        dataQualityScore: 0.95,
      ),
      locationTags: ['北京', '华北'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_031',
        name: '伍前红',
        university: '北京航空航天大学',
        college: '网络空间安全学院',
        title: '教授',
        researchFields: ['人工智能安全', '密码学', '区块链', '数据安全', '隐私计算'],
        bio:
            '北航网络空间安全学院教授，研究去中心化人工智能、应用密码学、分布式系统安全、数据安全与隐私、区块链和数字货币。公开主页显示其长期从事密码学、信息安全、隐私保护及 AI 安全方向研究。',
        homepageUrl: 'https://cst.buaa.edu.cn/info/1111/2774.htm',
        sourceUrl: 'https://cst.buaa.edu.cn/info/1111/2774.htm',
        updatedAt: '2026-06-04',
        dataQualityScore: 0.88,
      ),
      locationTags: ['北京', '华北'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_032',
        name: '李宣东',
        university: '南京大学',
        college: '智能软件与工程学院',
        title: '教授',
        researchFields: ['软件工程', '可信软件', '形式化方法'],
        bio:
            '南京大学智能软件与工程学院教授、博士生导师，教学与科研涉及软件工程、可信软件和形式化方法，部分研究工作获国家科技进步二等奖。曾任南京大学计算机科学与技术系系主任、软件学院院长，兼任中国计算机学会软件工程专业委员会主任等职务。',
        homepageUrl: 'http://cs.nju.edu.cn/lixuandong',
        sourceUrl: 'http://cs.nju.edu.cn/lixuandong',
        updatedAt: '2026-06-05',
        dataQualityScore: 0.9,
      ),
      locationTags: ['江苏', '南京', '江浙沪', '华东'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_033',
        name: '蒋智威',
        university: '南京大学',
        college: '智能软件与工程学院',
        title: '助理教授',
        researchFields: ['自然语言处理', '深度学习', '大语言模型', '多模态'],
        bio:
            '南京大学智能软件与工程学院助理教授、博士生导师，研究自然语言处理和深度学习，包括大语言模型、文本表示学习、文本质量评估、情感分析、多模态处理和软工文本挖掘。近年来在 ACL、NeurIPS、ICLR、SIGIR、WWW 等会议发表论文。',
        homepageUrl: 'https://ise.nju.edu.cn/info/1007/2561.htm',
        sourceUrl: 'https://ise.nju.edu.cn/info/1007/2561.htm',
        updatedAt: '2026-06-05',
        dataQualityScore: 0.9,
      ),
      locationTags: ['江苏', '南京', '江浙沪', '华东'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_034',
        name: '孟晴开',
        university: '南京大学',
        college: '智能软件与工程学院',
        title: '助理教授',
        researchFields: ['数据中心网络', '网络传输协议', '机器学习系统'],
        bio:
            '南京大学智能软件与工程学院助理教授、特聘研究员、博士生导师，研究数据中心网络、网络传输协议和机器学习系统。公开资料显示其以第一或通讯作者在 USENIX NSDI、IEEE INFOCOM、IEEE/ACM TON 等会议期刊发表论文。',
        homepageUrl: 'https://ise.nju.edu.cn/info/1451/2191.htm',
        sourceUrl: 'https://ise.nju.edu.cn/info/1451/2191.htm',
        updatedAt: '2026-06-05',
        dataQualityScore: 0.89,
      ),
      locationTags: ['江苏', '南京', '江浙沪', '华东'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_035',
        name: '殷亚凤',
        university: '南京大学',
        college: '智能软件与工程学院',
        title: '助理教授',
        researchFields: ['计算机视觉', '多模态', '智能感知', '模式识别'],
        bio:
            '南京大学智能软件与工程学院助理教授、特聘研究员、博士生导师，研究智能感知与视觉计算，包括多模态感知、人体动作识别、手语翻译与生成。公开资料显示其主持国家自然科学基金项目并在 TMC、TC、UbiComp、INFOCOM、ACM MM、CVPR、IJCAI 等发表论文。',
        homepageUrl: 'https://yafengnju.github.io',
        sourceUrl: 'https://ise.nju.edu.cn/info/1007/2571.htm',
        updatedAt: '2026-06-05',
        dataQualityScore: 0.88,
      ),
      locationTags: ['江苏', '南京', '江浙沪', '华东'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_036',
        name: '刘明谋',
        university: '南京大学',
        college: '智能软件与工程学院',
        title: '副教授',
        researchFields: ['算法设计', '数据结构', '理论计算机科学'],
        bio:
            '南京大学智能软件与工程学院副教授，入选国家级青年人才项目。主要从事理论计算机科学研究，兴趣涵盖算法设计与计算复杂度分析，重点关注数据结构理论、哈希算法及降维技术，在 STOC、SPAA、PODS、ICALP 等会议发表论文。',
        homepageUrl: 'https://ise.nju.edu.cn/info/1441/2111.htm',
        sourceUrl: 'https://ise.nju.edu.cn/info/1441/2111.htm',
        updatedAt: '2026-06-05',
        dataQualityScore: 0.87,
      ),
      locationTags: ['江苏', '南京', '江浙沪', '华东'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_037',
        name: '王凯',
        university: '南京大学',
        college: '电子科学与工程学院',
        title: '助理教授',
        researchFields: ['类脑智能', '计算机视觉', '集成电路', 'AI加速器'],
        bio:
            '南京大学电子科学与工程学院准聘助理教授、特聘研究员、博士生导师，聚焦受人类视觉系统启发的类脑视觉感知，覆盖认知架构、智能感知算法与端侧高能效推理芯片。公开资料显示其主持科研经费近千万元并获授权发明专利多项。',
        homepageUrl: 'https://www.sensingvisionlab.com',
        sourceUrl: 'https://www.sensingvisionlab.com',
        updatedAt: '2026-06-05',
        dataQualityScore: 0.87,
      ),
      locationTags: ['江苏', '南京', '江浙沪', '华东'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_038',
        name: '禹继国',
        university: '电子科技大学',
        college: '信息与软件工程学院（示范性软件学院）',
        title: '教授',
        researchFields: ['网络安全', '数据安全', '隐私计算', '区块链', '人工智能安全'],
        bio:
            '电子科技大学信息与软件工程学院教授、博导，IEEE Fellow、AAIA Fellow、AIIA Fellow。研究智能物联网、AI 安全、网络与数据安全及隐私保护、区块链、云边协同计算等方向，公开资料显示其发表论文 300 余篇、Google 学术引用过万。',
        homepageUrl: 'https://sise.uestc.edu.cn/info/1035/13088.htm',
        sourceUrl: 'https://sise.uestc.edu.cn/info/1035/13088.htm',
        updatedAt: '2026-06-06',
        dataQualityScore: 0.94,
      ),
      locationTags: ['四川', '成都', '西南'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_039',
        name: '张小松',
        university: '电子科技大学',
        college: '信息与软件工程学院（示范性软件学院）',
        title: '教授',
        researchFields: ['网络安全', '人工智能安全', '软件安全', '数据安全'],
        bio:
            '电子科技大学信息与软件工程学院教授、博导，国家级人才，长期从事网络安全研究，是我国计算机网络对抗方向的重要学者。公开资料显示其围绕威胁感知、检测防御、追踪溯源开展系统研究，以第一完成人获国家科技进步一等奖和二等奖。',
        homepageUrl: 'https://sise.uestc.edu.cn/info/1035/13033.htm',
        sourceUrl: 'https://sise.uestc.edu.cn/info/1035/13033.htm',
        updatedAt: '2026-06-06',
        dataQualityScore: 0.95,
      ),
      locationTags: ['四川', '成都', '西南'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_040',
        name: '秦臻',
        university: '电子科技大学',
        college: '信息与软件工程学院（示范性软件学院）',
        title: '教授',
        researchFields: ['人工智能安全', '数据安全', '隐私计算', '物联网'],
        bio:
            '电子科技大学信息与软件工程学院教授、博士生导师，入选国家高层次人才和四川省杰出青年科技人才。研究数据融合分析、人工智能安全、移动互联网、工业物联网和数据隐私保护，在 IEEE TFS、IEEE IoTJ、IEEE TNNLS 等发表论文。',
        homepageUrl: 'https://sise.uestc.edu.cn/info/1035/5646.htm',
        sourceUrl: 'https://sise.uestc.edu.cn/info/1035/5646.htm',
        updatedAt: '2026-06-06',
        dataQualityScore: 0.92,
      ),
      locationTags: ['四川', '成都', '西南'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_041',
        name: '叶飞',
        university: '电子科技大学',
        college: '信息与软件工程学院（示范性软件学院）',
        title: '教授',
        researchFields: ['机器视觉', '计算机视觉', '连续学习', '机器学习'],
        bio:
            '电子科技大学信息与软件工程学院教授、博士生导师，入选国家级青年人才，研究机器视觉与连续学习。公开资料显示其近五年以第一作者或通讯作者在 TPAMI、CVPR、AAAI、ICCV、NeurIPS 等期刊会议发表 CCF A 类及中科院一区论文 30 余篇。',
        homepageUrl: 'https://sise.uestc.edu.cn/info/1035/14109.htm',
        sourceUrl: 'https://sise.uestc.edu.cn/info/1035/14109.htm',
        updatedAt: '2026-06-06',
        dataQualityScore: 0.91,
      ),
      locationTags: ['四川', '成都', '西南'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_042',
        name: '陈飞宇',
        university: '电子科技大学',
        college: '信息与通信工程学院',
        title: '副教授',
        researchFields: ['多模态', '人工智能', '信息融合', '数据挖掘'],
        bio:
            '电子科技大学信息与通信工程学院副教授，研究多模态分析、多模态信息融合、语义挖掘和多模态序列协同建模。公开资料显示其在 IEEE TCYB、IEEE TNNLS、IEEE TMM、CVPR、ACM MM、AAAI、ICDE 等期刊会议发表论文。',
        homepageUrl: 'https://www.sice.uestc.edu.cn/info/1451/15223.htm',
        sourceUrl: 'https://www.sice.uestc.edu.cn/info/1451/15223.htm',
        updatedAt: '2026-06-06',
        dataQualityScore: 0.89,
      ),
      locationTags: ['四川', '成都', '西南'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_043',
        name: '黄文',
        university: '电子科技大学',
        college: '集成电路科学与工程学院（示范性微电子学院）',
        title: '教授',
        researchFields: ['集成电路', '智能传感', '计算机视觉', '模式识别'],
        bio:
            '电子科技大学集成电路科学与工程学院教授，围绕新型感算一体光电集成器件开展研究，方向包括光电探测与识别、智能仿生视觉新器件、红外识别和光电突触器件。公开资料显示其主持国家自然科学基金等项目，在 Nature Communications、IEEE EDL 等发表论文。',
        homepageUrl: 'https://icse.uestc.edu.cn/info/1812/6867.htm',
        sourceUrl: 'https://icse.uestc.edu.cn/info/1812/6867.htm',
        updatedAt: '2026-06-06',
        dataQualityScore: 0.9,
      ),
      locationTags: ['四川', '成都', '西南'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_044',
        name: '郭青',
        university: '南开大学',
        college: '计算机学院',
        title: '教授',
        researchFields: ['可靠感知', '人工智能安全', '对抗攻击', '计算机视觉'],
        bio:
            '南开大学计算机学院教授、博士生导师，国家级青年人才，多次入选斯坦福全球 Top 2% 科学家。研究可靠感知、AI 安全、对抗攻击与防御，曾获 ICME 最佳论文奖、ACM 优秀博士论文奖等荣誉。',
        homepageUrl:
            'https://cc.nankai.edu.cn/2021/0323/c37280a577810/page.htm',
        sourceUrl: 'https://cc.nankai.edu.cn/2021/0323/c37280a577810/page.htm',
        updatedAt: '2026-06-18',
        dataQualityScore: 0.94,
      ),
      locationTags: ['天津', '华北'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_045',
        name: '刘承威',
        university: '南开大学',
        college: '密码与网络空间安全学院',
        title: '教授',
        researchFields: ['软件安全', '软件供应链安全', '开源安全', '智能体安全'],
        bio:
            '南开大学密码与网络空间安全学院教授、博士生导师，国家级青年人才。研究软件安全、程序分析、开源软件安全、软件供应链安全和智能体软件安全与治理，围绕开源生态安全、漏洞分析与供应链风险识别开展系统研究。',
        homepageUrl:
            'https://cyber.nankai.edu.cn/2021/0323/c13838a592256/page.htm',
        sourceUrl:
            'https://cyber.nankai.edu.cn/2021/0323/c13838a592256/page.htm',
        updatedAt: '2026-06-18',
        dataQualityScore: 0.92,
      ),
      locationTags: ['天津', '华北'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_046',
        name: '刘哲理',
        university: '南开大学',
        college: '密码与网络空间安全学院',
        title: '教授',
        researchFields: ['数据安全', '人工智能安全', '隐私计算', '网络安全'],
        bio:
            '南开大学计算机学院院长、密码与网络空间安全学院常务副院长，国家高层次人才，数据与智能系统安全教育部重点实验室主任。研究数据安全与人工智能安全，近年在 USENIX Security、CCS、NDSS、S&P、VLDB、ASE、ISSTA 等发表论文。',
        homepageUrl:
            'https://cyber.nankai.edu.cn/2021/0323/c13838a551995/page.htm',
        sourceUrl:
            'https://cyber.nankai.edu.cn/2021/0323/c13838a551995/page.htm',
        updatedAt: '2026-06-18',
        dataQualityScore: 0.93,
      ),
      locationTags: ['天津', '华北'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_047',
        name: '韩建达',
        university: '南开大学',
        college: '人工智能学院',
        title: '杰出教授',
        researchFields: ['机器人', '医疗机器人', '智能控制', '自主行为'],
        bio:
            '南开大学人工智能学院杰出教授、博士研究生导师，长期从事机器人技术与系统研究，方向包括机器人自主行为共性技术、医疗手术与康复机器人、移动机器人技术与系统。公开资料显示其主持 973、863、国家重点研发计划等项目。',
        homepageUrl: 'https://ai.nankai.edu.cn/info/1033/2796.htm',
        sourceUrl: 'https://ai.nankai.edu.cn/info/1033/2796.htm',
        updatedAt: '2026-06-18',
        dataQualityScore: 0.91,
      ),
      locationTags: ['天津', '华北'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_048',
        name: '郑骁庆',
        university: '复旦大学',
        college: '计算与智能创新学院',
        title: '副教授',
        researchFields: ['自然语言处理', '机器学习', '大模型'],
        bio:
            '复旦大学计算与智能创新学院副教授、博士生导师，主要研究自然语言处理和机器学习。公开资料显示其在 Computational Linguistics、ICML、NeurIPS、ICLR、ACL、EMNLP 等自然语言处理和人工智能顶级会议期刊发表论文 80 余篇。',
        homepageUrl: 'http://ai.fudan.edu.cn/zxq/list.htm',
        sourceUrl: 'http://ai.fudan.edu.cn/zxq/list.htm',
        updatedAt: '2026-06-17',
        dataQualityScore: 0.92,
      ),
      locationTags: ['上海', '江浙沪', '华东'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_049',
        name: '陈碧欢',
        university: '复旦大学',
        college: '计算与智能创新学院',
        title: '副教授',
        researchFields: ['软件安全', 'AI系统工程', '软件供应链安全'],
        bio:
            '复旦大学计算与智能创新学院副教授，研究软件安全与 AI 系统工程。公开资料显示其成果发表于 ICSE、FSE、S&P、USENIX Security、TSE、TIFS 等会议期刊，获多次 ACM SIGSOFT 与 IEEE TCSE 杰出论文奖，并研制开源风险治理平台。',
        homepageUrl: 'http://ai.fudan.edu.cn/cbh/list.htm',
        sourceUrl: 'http://ai.fudan.edu.cn/cbh/list.htm',
        updatedAt: '2026-06-17',
        dataQualityScore: 0.92,
      ),
      locationTags: ['上海', '江浙沪', '华东'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_050',
        name: '潘旭东',
        university: '复旦大学',
        college: '计算与智能创新学院',
        title: '助理研究员',
        researchFields: ['大模型安全', '大模型治理', '智能体安全', '人工智能安全'],
        bio:
            '复旦大学计算与智能创新学院助理研究员，研究大模型安全与治理、大模型安全合规评估、智能体安全攻防和前沿 AI 风险治理。公开资料显示其在 TPAMI、ICML、NeurIPS、IEEE S&P、USENIX Security 等发表论文，并揭示多类商用大模型安全风险。',
        homepageUrl: 'http://ai.fudan.edu.cn/pxd/list.htm',
        sourceUrl: 'http://ai.fudan.edu.cn/pxd/list.htm',
        updatedAt: '2026-06-17',
        dataQualityScore: 0.9,
      ),
      locationTags: ['上海', '江浙沪', '华东'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_051',
        name: '范益波',
        university: '复旦大学',
        college: '微电子学院',
        title: '教授',
        researchFields: ['NPU', '图像处理器', '机器学习', '异构计算', '云计算'],
        bio:
            '复旦大学微电子学院教授、博导，视频图像处理器实验室负责人，专注视频编解码 VPU、图像 ISP 与神经网络 NPU 处理器芯片架构研究。公开资料显示其承担国家重点研发、重大科研仪器研制和自然科学基金重点项目，发表论文 200 余篇。',
        homepageUrl: 'https://sme.fudan.edu.cn/5f/d2/c31143a352210/page.htm',
        sourceUrl: 'https://sme.fudan.edu.cn/5f/d2/c31143a352210/page.htm',
        updatedAt: '2026-06-16',
        dataQualityScore: 0.91,
      ),
      locationTags: ['上海', '江浙沪', '华东'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_052',
        name: '冯君',
        university: '华中科技大学',
        college: '网络空间安全学院',
        title: '副教授',
        researchFields: ['数据安全', '隐私计算', '人工智能安全', '区块链'],
        bio:
            '华中科技大学网络空间安全学院副教授，研究大数据安全与隐私保护、人工智能安全、深度学习和区块链。公开资料显示其发表论文 50 余篇，包括 IEEE TDSC、IEEE TC、IEEE TIFS、AAAI、ACM TOIT 等，并主持国家自然科学基金项目。',
        homepageUrl: 'http://faculty.hust.edu.cn/fengjun6/zh_CN/index.htm',
        sourceUrl: 'http://faculty.hust.edu.cn/fengjun6/zh_CN/index.htm',
        updatedAt: '2026-06-30',
        dataQualityScore: 0.9,
      ),
      locationTags: ['湖北', '武汉', '华中'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_053',
        name: '李远征',
        university: '华中科技大学',
        college: '人工智能与自动化学院',
        title: '教授',
        researchFields: ['深度学习', '智能电网', '能源互联网', '大数据'],
        bio:
            '华中科技大学人工智能与自动化学院教授、国家优秀青年基金获得者、博士生导师，研究人工智能赋能的智能电网与能源互联网、基于深度学习的大数据分析优化及预测。公开资料显示其在 Nature Reviews Electrical Engineering、Proceedings of the IEEE 和 IEEE Transactions 等发表论文。',
        homepageUrl: 'http://faculty.hust.edu.cn/liyuanzheng2/zh_CN/index.htm',
        sourceUrl: 'http://faculty.hust.edu.cn/liyuanzheng2/zh_CN/index.htm',
        updatedAt: '2026-06-30',
        dataQualityScore: 0.92,
      ),
      locationTags: ['湖北', '武汉', '华中'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_054',
        name: '袁烨',
        university: '华中科技大学',
        college: '人工智能与自动化学院',
        title: '教授',
        researchFields: ['物理AI', '智能制造', '机器人', '智能控制'],
        bio:
            '华中科技大学人工智能与自动化学院教授、博士生导师，国家领军人才，研究物理 AI 系统建模优化理论及工程应用、系统辨识优化理论算法和机器人化智能制造。公开资料显示其主持国家基金委青 A、重大研究计划和科技部重点研发课题。',
        homepageUrl:
            'http://faculty.hust.edu.cn/yeyuan/zh_CN/index/752531/list/index.htm',
        sourceUrl:
            'http://faculty.hust.edu.cn/yeyuan/zh_CN/index/752531/list/index.htm',
        updatedAt: '2026-06-30',
        dataQualityScore: 0.93,
      ),
      locationTags: ['湖北', '武汉', '华中'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_055',
        name: '董燕',
        university: '华中科技大学',
        college: '电子信息与通信学院',
        title: '教授',
        researchFields: ['无线通信', '卫星通信', '信号处理', '机器学习'],
        bio:
            '华中科技大学电子信息与通信学院教授，研究无线通信系统、卫星通信网络、自适应传输、无线传感器网络、通信信号处理、调制编码和机器学习。公开资料显示其承担自然科学基金重大研究计划、科技部重点研发计划、863 等多项课题。',
        homepageUrl: 'http://eic.hust.edu.cn/professor/dongyan/index.htm',
        sourceUrl: 'http://eic.hust.edu.cn/professor/dongyan/index.htm',
        updatedAt: '2026-06-30',
        dataQualityScore: 0.88,
      ),
      locationTags: ['湖北', '武汉', '华中'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_056',
        name: '高阳',
        university: '北京航空航天大学',
        college: '计算机学院',
        title: '教授',
        researchFields: ['虚拟现实', '计算机图形学', '智慧医疗', '物理仿真'],
        bio:
            '北京航空航天大学计算机学院教授、博士生导师、国家级青年人才，依托虚拟现实技术与系统全国重点实验室开展虚实融合场景建模仿真与交互、VR+医疗康复应用、可视化物理仿真和真实感绘制研究，在 SIGGRAPH、IEEE VR、TVCG 等发表论文。',
        homepageUrl: 'https://scse.buaa.edu.cn/info/1078/12180.htm',
        sourceUrl: 'https://scse.buaa.edu.cn/info/1078/12180.htm',
        updatedAt: '2026-06-04',
        dataQualityScore: 0.92,
      ),
      locationTags: ['北京', '华北'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_057',
        name: '李帅',
        university: '北京航空航天大学',
        college: '计算机学院',
        title: '教授',
        researchFields: ['虚拟现实', '智慧医疗', '具身智能', '计算机视觉'],
        bio:
            '北京航空航天大学计算机学院教授、博士生导师、国家级领军人才，计算机学院副院长，长期从事虚拟现实、智慧医疗和具身智能研究。公开资料显示其在 TPAMI、SIGGRAPH、TVCG、IJCV、TIP、AAAI、ICCV、CVPR 等发表论文 140 多篇。',
        homepageUrl: 'https://scse.buaa.edu.cn/info/1078/7416.htm',
        sourceUrl: 'https://scse.buaa.edu.cn/info/1078/7416.htm',
        updatedAt: '2026-06-04',
        dataQualityScore: 0.95,
      ),
      locationTags: ['北京', '华北'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_058',
        name: '马宇晴',
        university: '北京航空航天大学',
        college: '人工智能学院',
        title: '副教授',
        researchFields: ['多模态大模型', '安全对齐', '智能体推理', '智慧医疗'],
        bio:
            '北京航空航天大学人工智能学院副教授、硕士生导师，研究多模态大模型安全对齐、智能体推理和智能医疗。公开资料显示其在 NeurIPS、ICML、ICLR、CVPR、ACL、WWW、AAAI、EMNLP、TNNLS、TCYB、TIP 等发表论文 50 余篇。',
        homepageUrl: 'https://iai.buaa.edu.cn/info/1013/2689.htm',
        sourceUrl: 'https://iai.buaa.edu.cn/info/1013/2689.htm',
        updatedAt: '2026-06-04',
        dataQualityScore: 0.91,
      ),
      locationTags: ['北京', '华北'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_059',
        name: '周号益',
        university: '北京航空航天大学',
        college: '软件学院',
        title: '副教授',
        researchFields: ['大数据', '机器学习', '时序预测', 'AI4S'],
        bio:
            '北京航空航天大学软件学院副教授、国家级青年人才，研究大数据、机器学习、时序预测和 AI4S 智算软件。公开资料显示其在 AIJ、TKDE、ICML、NeurIPS、CVPR、KDD 等发表论文，曾获 AAAI 最佳论文奖和 IEEE IWQoS 最佳论文奖。',
        homepageUrl:
            'https://soft.buaa.edu.cn/teachershouw.jsp?urltype=news.NewsContentUrl&wbtreeid=1372&wbnewsid=12332',
        sourceUrl:
            'https://soft.buaa.edu.cn/teachershouw.jsp?urltype=news.NewsContentUrl&wbtreeid=1372&wbnewsid=12332',
        updatedAt: '2026-06-04',
        dataQualityScore: 0.92,
      ),
      locationTags: ['北京', '华北'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_060',
        name: '武港山',
        university: '南京大学',
        college: '智能软件与工程学院',
        title: '教授',
        researchFields: ['计算机视觉', '信息检索', 'Web智能信息处理', '多媒体'],
        bio:
            '南京大学智能软件与工程学院教授、博士生导师，南京大学多媒体教研室主任。主要从事计算机视觉计算、多媒体信息检索、Web 智能信息处理、数字博物馆和海量地质数据处理等研究，主持或承担国家重大专项、863、自然科学基金重点等项目。',
        homepageUrl: 'https://ise.nju.edu.cn/',
        sourceUrl: 'https://ise.nju.edu.cn/',
        updatedAt: '2026-06-05',
        dataQualityScore: 0.83,
      ),
      locationTags: ['江苏', '南京', '江浙沪', '华东'],
      limitations: ['公开数据中未提供个人主页直链'],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_061',
        name: '钮鑫涛',
        university: '南京大学',
        college: '智能软件与工程学院',
        title: '助理教授',
        researchFields: ['软件测试', '故障定位', '软件分析', '神经网络'],
        bio:
            '南京大学智能软件与工程学院助理教授、博士生导师，研究软件测试、故障定位、软件分析和基础软件测试与分析。公开资料显示其在 TSE、TOSEM、ICSE、FSE、ICST 等软件工程期刊会议发表论文，相关成果已在企业应用。',
        homepageUrl: 'https://ise.nju.edu.cn/info/1007/2491.htm',
        sourceUrl: 'https://ise.nju.edu.cn/info/1007/2491.htm',
        updatedAt: '2026-06-05',
        dataQualityScore: 0.88,
      ),
      locationTags: ['江苏', '南京', '江浙沪', '华东'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_062',
        name: '王智彬',
        university: '南京大学',
        college: '智能软件与工程学院',
        title: '助理研究员',
        researchFields: ['图计算', '大模型推理', '高性能计算', '数据库'],
        bio:
            '南京大学智能软件与工程学院助理研究员，研究加速图计算和大模型推理。公开资料显示其在系统和数据库领域发表 CCF A 类论文 10 余篇，作为第一作者发表南大第一篇 SIGMOD 论文和第一篇 PPoPP 论文，并曾在阿里巴巴达摩院 GraphScope 团队实习。',
        homepageUrl: 'https://ise.nju.edu.cn/info/1431/1991.htm',
        sourceUrl: 'https://ise.nju.edu.cn/info/1431/1991.htm',
        updatedAt: '2026-06-05',
        dataQualityScore: 0.87,
      ),
      locationTags: ['江苏', '南京', '江浙沪', '华东'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_063',
        name: '赵阳明',
        university: '南京大学',
        college: '智能软件与工程学院',
        title: '副教授',
        researchFields: ['量子信息', '网络通信', '计算机网络'],
        bio:
            '南京大学智能软件与工程学院副教授，研究量子信息技术和网络通信技术，入选中科院人才计划和安徽省海外引才计划创新项目。公开资料显示其发表论文 80 余篇，包括 TON、TPDS、TC、TMC、INFOCOM、NSDI 等国际一流期刊与会议。',
        homepageUrl: 'https://ise.nju.edu.cn/info/1461/2201.htm',
        sourceUrl: 'https://ise.nju.edu.cn/info/1461/2201.htm',
        updatedAt: '2026-06-05',
        dataQualityScore: 0.87,
      ),
      locationTags: ['江苏', '南京', '江浙沪', '华东'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_064',
        name: '张凤荔',
        university: '电子科技大学',
        college: '信息与软件工程学院（示范性软件学院）',
        title: '教授',
        researchFields: ['软件工程', '网络安全', '云计算', '大数据', '智能计算'],
        bio:
            '电子科技大学信息与软件工程学院教授、博士生导师，研究软件理论、网络安全与网络工程、云计算与大数据、智能计算。公开资料显示其长期从事计算机教学与科研，作为负责人或主研完成多项国家重点科技攻关项目和应用系统项目。',
        homepageUrl: 'https://sise.uestc.edu.cn/info/1035/5658.htm',
        sourceUrl: 'https://sise.uestc.edu.cn/info/1035/5658.htm',
        updatedAt: '2026-06-06',
        dataQualityScore: 0.87,
      ),
      locationTags: ['四川', '成都', '西南'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_065',
        name: '罗萍',
        university: '电子科技大学',
        college: '集成电路科学与工程学院（示范性微电子学院）',
        title: '教授',
        researchFields: ['集成电路', '低功耗设计', '智能计算', '能量采集'],
        bio:
            '电子科技大学集成电路科学与工程学院教授、博导，研究智能功率集成电路与系统设计、高效电源管理、模拟集成电路抗辐射加固、能量采集和低功耗数模混合集成技术，主持国家重大专项、自然科学基金、863 子项目等。',
        homepageUrl: 'https://icse.uestc.edu.cn/info/1812/6530.htm',
        sourceUrl: 'https://icse.uestc.edu.cn/info/1812/6530.htm',
        updatedAt: '2026-06-06',
        dataQualityScore: 0.89,
      ),
      locationTags: ['四川', '成都', '西南'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_066',
        name: '黄承赓',
        university: '电子科技大学',
        college: '自动化工程学院',
        title: '副教授',
        researchFields: ['工业大数据', '人工智能', '大语言模型', '智能体推理', '故障诊断'],
        bio:
            '电子科技大学自动化工程学院副教授，研究故障诊断预测与健康管理、工业大数据与人工智能、大语言模型与智能体及其在 DPHM 领域的工程化应用。公开资料显示其发表论文 45 篇，含 ESI 热点论文和高被引论文，主持国家自然科学基金青年基金等项目。',
        homepageUrl: 'https://www.auto.uestc.edu.cn/info/1092/7712.htm',
        sourceUrl: 'https://www.auto.uestc.edu.cn/info/1092/7712.htm',
        updatedAt: '2026-06-06',
        dataQualityScore: 0.88,
      ),
      locationTags: ['四川', '成都', '西南'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_067',
        name: '邵晋梁',
        university: '电子科技大学',
        college: '自动化工程学院',
        title: '教授',
        researchFields: ['群体智能', '无人机', '多智能体', '智能控制'],
        bio:
            '电子科技大学自动化工程学院教授，长期从事群体智能机理、多智能体系统协同控制、无人集群系统智能感知和协同定位研究。公开资料显示其发表论文 100 余篇，包括 IEEE TAC、Automatica、SIAM JCO、IEEE TCYB、IEEE TKDE 等，授权发明专利 30 余项。',
        homepageUrl: 'https://www.auto.uestc.edu.cn/info/1168/4337.htm',
        sourceUrl: 'https://www.auto.uestc.edu.cn/info/1168/4337.htm',
        updatedAt: '2026-06-06',
        dataQualityScore: 0.89,
      ),
      locationTags: ['四川', '成都', '西南'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_068',
        name: '贾岩',
        university: '南开大学',
        college: '密码与网络空间安全学院',
        title: '副教授',
        researchFields: ['物联网安全', '漏洞挖掘', '应用系统安全', '隐私计算'],
        bio:
            '南开大学密码与网络空间安全学院副教授、博导，南开大学百名青年学科带头人，研究物联网安全与隐私、漏洞挖掘与脆弱性分析、应用系统安全与用户侧安全。公开资料显示其曾发现多类国际影响力物联网平台安全问题并获多个厂商致谢。',
        homepageUrl:
            'https://cyber.nankai.edu.cn/2021/0323/c37293a575913/page.htm',
        sourceUrl:
            'https://cyber.nankai.edu.cn/2021/0323/c37293a575913/page.htm',
        updatedAt: '2026-06-18',
        dataQualityScore: 0.9,
      ),
      locationTags: ['天津', '华北'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_069',
        name: '陈森',
        university: '南开大学',
        college: '密码与网络空间安全学院',
        title: '教授',
        researchFields: ['软件安全', '智能体安全', '软件供应链安全'],
        bio:
            '南开大学密码与网络空间安全学院教授，软件安全实验室负责人之一，研究软件安全、智能体软件安全与软件供应链安全。公开资料显示其获 ACM SIGSOFT Early Career Researcher Award，发表高水平论文 100 余篇并获得 CCF-A 类会议杰出论文奖多项。',
        homepageUrl:
            'https://cyber.nankai.edu.cn/2021/0323/c13838a569226/page.htm',
        sourceUrl:
            'https://cyber.nankai.edu.cn/2021/0323/c13838a569226/page.htm',
        updatedAt: '2026-06-18',
        dataQualityScore: 0.93,
      ),
      locationTags: ['天津', '华北'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_070',
        name: '李涛',
        university: '南开大学',
        college: '密码与网络空间安全学院',
        title: '教授',
        researchFields: ['异构计算', '智能物联网', '区块链', '人工智能'],
        bio:
            '南开大学计算机学院、密码与网络空间安全学院教授、博导，新一代人工智能发展战略研究院相关负责人。研究异构计算、智能物联网、区块链系统和人工智能，兼具计算机体系结构、物联网和区块链系统方向积累。',
        homepageUrl:
            'https://cyber.nankai.edu.cn/2021/0323/c13838a552001/page.htm',
        sourceUrl:
            'https://cyber.nankai.edu.cn/2021/0323/c13838a552001/page.htm',
        updatedAt: '2026-06-18',
        dataQualityScore: 0.91,
      ),
      locationTags: ['天津', '华北'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_071',
        name: '徐敬东',
        university: '南开大学',
        college: '密码与网络空间安全学院',
        title: '教授',
        researchFields: ['计算机网络', '移动边缘计算', '视频传输', '软件定义网络', '网络安全'],
        bio:
            '南开大学计算机学院、网络安全学院教授、博士生导师，计算机网络与信息安全研究室负责人。研究计算机网络、移动边缘计算、视频传输、软件定义网络和网络安全，主持国家自然科学基金、天津市科技重大专项等项目。',
        homepageUrl:
            'https://cyber.nankai.edu.cn/2021/0323/c13838a551982/page.htm',
        sourceUrl:
            'https://cyber.nankai.edu.cn/2021/0323/c13838a551982/page.htm',
        updatedAt: '2026-06-18',
        dataQualityScore: 0.9,
      ),
      locationTags: ['天津', '华北'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_072',
        name: '刘进超',
        university: '南开大学',
        college: '人工智能学院',
        title: '教授',
        researchFields: ['机器学习', '深度学习', '机器视觉', '图像处理', 'AI4S'],
        bio:
            '南开大学人工智能学院教授、博士生导师，天津市高层次青年人才，研究机器学习/深度学习、机器视觉、图像处理与分析，以及交叉学科中的人工智能。公开资料显示其论文发表于 TPAMI、TIP、TASE、TIE、TMI、Light: Science & Applications 等期刊。',
        homepageUrl: 'https://ai.nankai.edu.cn/info/1033/6233.htm',
        sourceUrl: 'https://ai.nankai.edu.cn/info/1033/6233.htm',
        updatedAt: '2026-06-18',
        dataQualityScore: 0.91,
      ),
      locationTags: ['天津', '华北'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_073',
        name: '范玲玲',
        university: '南开大学',
        college: '密码与网络空间安全学院',
        title: '副教授',
        researchFields: ['软件测试', '软件安全', '开源软件治理', '软件工程'],
        bio:
            '南开大学密码与网络空间安全学院副教授、博士生导师，百青青年学科带头人，研究软件测试、软件安全和开源软件治理。公开资料显示其近五年发表 CCF-A/SCI 一区论文 30 余篇，包括 ICSE、S&P、ASE、TSE、TDSC、TOSEM、FSE 等，并多次获 ICSE 杰出论文奖。',
        homepageUrl:
            'https://cyber.nankai.edu.cn/2021/0323/c37293a575914/page.htm',
        sourceUrl:
            'https://cyber.nankai.edu.cn/2021/0323/c37293a575914/page.htm',
        updatedAt: '2026-06-18',
        dataQualityScore: 0.9,
      ),
      locationTags: ['天津', '华北'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_074',
        name: '卢冶',
        university: '南开大学',
        college: '密码与网络空间安全学院',
        title: '教授',
        researchFields: ['智能处理器', '嵌入式系统', '异构计算', '系统安全', '框架工具链'],
        bio:
            '南开大学密码与网络空间安全学院教授、博士生导师，南开大学百青计划获得者，研究智能处理器芯片与系统、系统安全、高性能嵌入式、异构计算、端侧异构智能加速芯片设计和框架工具链优化，主持国家自然科学基金等项目。',
        homepageUrl:
            'https://cyber.nankai.edu.cn/2021/0323/c37289a581553/page.htm',
        sourceUrl:
            'https://cyber.nankai.edu.cn/2021/0323/c37289a581553/page.htm',
        updatedAt: '2026-06-18',
        dataQualityScore: 0.9,
      ),
      locationTags: ['天津', '华北'],
      limitations: [],
    ),
    _Fixture(
      professor: Professor(
        id: 'p_075',
        name: '刘晗',
        university: '南开大学',
        college: '计算机学院',
        title: '副教授',
        researchFields: ['软件安全', '智能合约安全', '软件供应链安全'],
        bio:
            '南开大学计算机学院副教授、博士生导师，百名青年学科带头人，研究软件安全、智能合约安全和软件供应链安全。公开资料显示其成果发表于 USENIX Security、ASE、ICSE、FSE、ISSTA、TSE 等安全与软件工程顶级会议期刊，并获 ACM SIGSOFT Distinguished Paper Award。',
        homepageUrl:
            'https://cc.nankai.edu.cn/2021/0323/c37281a592304/page.htm',
        sourceUrl: 'https://cc.nankai.edu.cn/2021/0323/c37281a592304/page.htm',
        updatedAt: '2026-06-18',
        dataQualityScore: 0.9,
      ),
      locationTags: ['天津', '华北'],
      limitations: [],
    ),
  ];
}

class _Fixture {
  const _Fixture({
    required this.professor,
    required this.locationTags,
    required this.limitations,
  });

  final Professor professor;
  final List<String> locationTags;
  final List<String> limitations;
}

class _Scored {
  const _Scored(this.fixture, this.score, this.matchedFields);

  final _Fixture fixture;
  final int score;
  final List<String> matchedFields;
}
