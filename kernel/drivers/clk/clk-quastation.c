// SPDX-License-Identifier: GPL-2.0-or-later
/* Experimental Qua clock provider with RTD1295 VE muxes and MNO PLLs. */
#include <linux/clk-provider.h>
#include <linux/delay.h>
#include <linux/io.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/slab.h>

static DEFINE_SPINLOCK(qua_gate_lock);
struct qua_pll { struct clk_hw hw; void __iomem *reg, *power; };
#define to_qua_pll(x) container_of(x, struct qua_pll, hw)
static unsigned long qua_pll_recalc(struct clk_hw *hw, unsigned long parent)
{
 u32 v = readl(to_qua_pll(hw)->reg);
 u32 m = (v >> 4) & 0xff, n = (v >> 12) & 3, o = (v >> 17) & 3;
 return div_u64((u64)parent * (m + 2), (n + 1) * (o + 1));
}
static int qua_pll_determine(struct clk_hw *hw, struct clk_rate_request *req)
{
 static const u32 rates[] = {189000000,270000000,405000000,432000000,459000000,486000000,513000000,540000000,567000000,594000000,648000000,675000000,702000000,715000000};
 unsigned int i; for (i = 0; i < ARRAY_SIZE(rates); i++) if (req->rate == rates[i]) return 0;
 return -EINVAL;
}
static int qua_pll_set(struct clk_hw *hw, unsigned long rate, unsigned long parent)
{
 static const struct { u32 rate, mno; } rates[] = {
  {189000000,5<<4},{270000000,8<<4},{405000000,13<<4},{432000000,14<<4},
  {459000000,15<<4},{486000000,16<<4},{513000000,17<<4},{540000000,18<<4},
  {567000000,19<<4},{594000000,20<<4},{648000000,22<<4},{675000000,23<<4},
  {702000000,24<<4},{715000000,(51<<4)|(1<<12)} };
 struct qua_pll *p = to_qua_pll(hw); unsigned long flags; u32 v; unsigned int i;
 for (i = 0; i < ARRAY_SIZE(rates); i++) if (rate == rates[i].rate) break;
 if (i == ARRAY_SIZE(rates)) return -EINVAL;
 spin_lock_irqsave(&qua_gate_lock, flags); v = readl(p->reg);
 writel((v & ~0x63ff0) | rates[i].mno, p->reg); spin_unlock_irqrestore(&qua_gate_lock, flags);
 return 0;
}
static int qua_pll_prepare(struct clk_hw *hw) { writel(3, to_qua_pll(hw)->power); udelay(200); return 0; }
static void qua_pll_unprepare(struct clk_hw *hw) { writel(4, to_qua_pll(hw)->power); }
static int qua_pll_is_prepared(struct clk_hw *hw) { return !!(readl(to_qua_pll(hw)->power) & 1); }
static const struct clk_ops qua_pll_ops = { .prepare=qua_pll_prepare, .unprepare=qua_pll_unprepare, .is_prepared=qua_pll_is_prepared, .recalc_rate=qua_pll_recalc, .determine_rate=qua_pll_determine, .set_rate=qua_pll_set };
static int qua_clocks_probe(struct platform_device *pdev)
{
 static const char * const names[] = { "qua-pcie0", "qua-pcie1", "qua-emmc", "qua-emmc-ip", "qua-usb", "qua-gpu", "qua-ve1", "qua-ve2", "qua-sysh", "qua-pll-ve1", "qua-pll-ve2", "qua-cr", "qua-sd-ip", "qua-uart1", "qua-uart2" };
 static const u8 offsets[] = {0,4,0,0,0,0}, bits[] = {1,5,24,28,4,11};
 static const char * const veparents[] = {"qua-sysh", "qua-pll-ve1", "qua-pll-ve2", "qua-pll-ve2"};
 struct device *dev=&pdev->dev; struct clk_hw_onecell_data *d; struct clk_hw *uart_ref; void __iomem *base, *crt; unsigned int i; int ret;
 base=devm_platform_ioremap_resource(pdev,0); if (IS_ERR(base)) return PTR_ERR(base);
 crt=devm_ioremap(dev,0x98000000,0x600); if (!crt) return -ENOMEM;
 d=devm_kzalloc(dev,struct_size(d,hws,ARRAY_SIZE(names)),GFP_KERNEL); if (!d) return -ENOMEM;
 d->num=ARRAY_SIZE(names);
 for (i=0;i<6;i++) {
  d->hws[i]=devm_clk_hw_register_gate(dev,names[i],of_clk_get_parent_name(dev->of_node,i==3?1:(i==5?2:0)),0,base+offsets[i],bits[i],0,&qua_gate_lock);
  if (IS_ERR(d->hws[i])) return PTR_ERR(d->hws[i]);
 }
 /* Current board bus PLL is fixed at 459 MHz; must be revalidated at boot. */
 if ((readl(crt+0x544)&0x7ffff)!=0x7000) {
  dev_err(dev, "VE clocks disabled: unexpected system bus PLL\n");
  d->num=6; return devm_of_clk_add_hw_provider(dev,of_clk_hw_onecell_get,d);
 }
 d->hws[8]=devm_clk_hw_register_fixed_rate(dev,"qua-sysh",NULL,0,459000000);
 if (IS_ERR(d->hws[8])) return PTR_ERR(d->hws[8]);
 for (i=0;i<2;i++) {
  struct qua_pll *pll=devm_kzalloc(dev,sizeof(*pll),GFP_KERNEL); struct clk_init_data init={}; struct clk_mux *mux; struct clk_gate *gate;
  if (!pll) return -ENOMEM;
  init.name=veparents[i+1]; init.ops=&qua_pll_ops; init.parent_names=(const char *[]){"osc27M"}; init.num_parents=1;
  pll->hw.init=&init; pll->reg=crt+(i?0x1d0:0x114); pll->power=crt+(i?0x1d4:0x118);
  ret=devm_clk_hw_register(dev,&pll->hw); if (ret) return ret; d->hws[9+i]=&pll->hw;
  mux=devm_kzalloc(dev,sizeof(*mux),GFP_KERNEL); gate=devm_kzalloc(dev,sizeof(*gate),GFP_KERNEL);
  if (!mux||!gate) return -ENOMEM;
  mux->reg=crt+0x4c; mux->shift=2*i; mux->mask=3; mux->lock=&qua_gate_lock;
  gate->reg=base; gate->bit_idx=12+i; gate->lock=&qua_gate_lock;
  d->hws[6+i]=clk_hw_register_composite(dev,names[6+i],veparents,4,&mux->hw,&clk_mux_ops,NULL,NULL,&gate->hw,&clk_gate_ops,CLK_SET_RATE_PARENT);
  if (IS_ERR(d->hws[6+i])) return PTR_ERR(d->hws[6+i]);
 }
 /* Keep the SD host clocks after the existing GPU and VE clock indices. */
 d->hws[11] = devm_clk_hw_register_gate(dev, names[11],
        of_clk_get_parent_name(dev->of_node, 0), CLK_IS_CRITICAL,
        base, 25, 0, &qua_gate_lock);
 if (IS_ERR(d->hws[11])) return PTR_ERR(d->hws[11]);
 d->hws[12] = devm_clk_hw_register_gate(dev, names[12],
        of_clk_get_parent_name(dev->of_node, 0), 0,
        base, 31, 0, &qua_gate_lock);
 if (IS_ERR(d->hws[12])) return PTR_ERR(d->hws[12]);
 uart_ref = devm_clk_hw_register_fixed_rate(dev, "qua-uart-ref", NULL, 0, 432000000);
 if (IS_ERR(uart_ref)) return PTR_ERR(uart_ref);
 for (i = 13; i <= 14; i++) {
  d->hws[i] = devm_clk_hw_register_gate(dev, names[i],
         "qua-uart-ref", 0,
         base + 4, i == 13 ? 28 : 27, 0, &qua_gate_lock);
  if (IS_ERR(d->hws[i])) return PTR_ERR(d->hws[i]);
 }
 return devm_of_clk_add_hw_provider(dev,of_clk_hw_onecell_get,d);
}
static const struct of_device_id qua_clock_match[]={{.compatible="kddi,quastation-gates"},{}};
static struct platform_driver qua_clock_driver={.probe=qua_clocks_probe,.driver={.name="qua-gates",.of_match_table=qua_clock_match}};
builtin_platform_driver(qua_clock_driver);
