# 2026_camp_a 版本演进

## v2026.04.18-dac-debug-ok

- 日期：2026-04-18
- 范围：2026_camp_a 工程更新入库
- 里程碑：`PL/src/dac_out.v` DAC 模块调试成功，已可稳定输出测试波形
- 配套：补充/更新 PL 与 PS 侧调试代码与脚本，纳入可回滚版本节点

### 恢复方式（建议）

- 使用标签恢复：`git checkout v2026.04.18-dac-debug-ok`
- 或使用提交恢复：`git log --oneline -- 2026_camp_a` 后按提交号 `git checkout <commit>`
