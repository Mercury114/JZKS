# 教师程序来源

`ex4_inst_ram.coe.gz` 至 `ex9_inst_ram.coe.gz` 是原课程COE字节的gzip无损压缩，未更改程序。
来源为个人已完成课设仓库 `la-course-design` 的 `course/fixtures/exN_obj/inst_ram.coe`，
来源提交 `6de28bfaf3fa0b7d55f7011616e244f2b30d98a1`。
各文件原字节长度与SHA256见 [manifest.json](manifest.json)。回归脚本先核对哈希，再解析COE和补零到RAM容量。

这些是教师输入程序，不是本次新编写的个人成果，也不是从待测CPU输出生成的答案。
原程序通过数码管写入报告自检功能点，本地回归分别要求29/33/39/46/47/58项按顺序通过。
新CPU接口、缓存、原confreg及同步RAM共同参与测试，但本地仿真不代替教师原XSim工程和平台验收。
