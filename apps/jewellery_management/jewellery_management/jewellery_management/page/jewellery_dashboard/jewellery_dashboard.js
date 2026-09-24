frappe.pages["jewellery-dashboard"].on_page_load = function (wrapper) {
	const page = frappe.ui.make_app_page({
		parent: wrapper,
		title: __("Sri Sai Krishna Jewellery"),
		single_column: true,
	});

	const PERIODS = [
		["Today", () => [frappe.datetime.get_today(), frappe.datetime.get_today()]],
		["Yesterday", () => {
			const y = frappe.datetime.add_days(frappe.datetime.get_today(), -1);
			return [y, y];
		}],
		["This Week", () => [frappe.datetime.week_start(), frappe.datetime.get_today()]],
		["This Month", () => [frappe.datetime.month_start(), frappe.datetime.get_today()]],
		["Last Month", () => {
			const first = frappe.datetime.add_months(frappe.datetime.month_start(), -1);
			const last = frappe.datetime.add_days(frappe.datetime.month_start(), -1);
			return [first, last];
		}],
		["This Year", () => [frappe.datetime.get_today().slice(0, 4) + "-04-01", frappe.datetime.get_today()]],
		["Last 6 Months", () => [frappe.datetime.add_months(frappe.datetime.get_today(), -6), frappe.datetime.get_today()]],
		["Last 12 Months", () => [frappe.datetime.add_months(frappe.datetime.get_today(), -12), frappe.datetime.get_today()]],
	];

	let from_field = page.add_field({		fieldname: "from_date", label: __("From"), fieldtype: "Date",
		default: frappe.datetime.month_start(), change: () => load("Custom"),
	});
	let to_field = page.add_field({
		fieldname: "to_date", label: __("To"), fieldtype: "Date",
		default: frappe.datetime.get_today(), change: () => load("Custom"),
	});

	const bar = $(`<div class="jm-periods" style="margin:12px 0;display:flex;gap:6px;flex-wrap:wrap;"></div>`);
	PERIODS.forEach(([label, fn]) => {
		$(`<button class="btn btn-sm btn-default">${label}</button>`)
			.on("click", () => {
				const [f, t] = fn();
				from_field.set_value(f);
				to_field.set_value(t);
				load(label);
			})
			.appendTo(bar);
	});
	$(page.body).append(bar);
	const body = $(`<div class="jm-dash"></div>`).appendTo(page.body);

	const fmt = (n) => format_currency(n || 0);
	const g = (n) => (n != null ? flt(n).toFixed(3) + " g" : "—");

	function kpi(title, value, sub, link) {
		return `<a href="${link || "#"}" style="text-decoration:none;color:inherit;">
			<div style="border:1px solid var(--border-color);border-radius:8px;padding:12px 14px;min-width:150px;flex:1;">
				<div style="font-size:12px;opacity:.7;">${title}</div>
				<div style="font-size:20px;font-weight:700;">${value}</div>
				<div style="font-size:12px;opacity:.7;">${sub || ""}</div>
			</div></a>`;
	}

	function load(label) {
		page._jm_label = label;
		const args = { from_date: from_field.get_value(), to_date: to_field.get_value() };
		body.html(`<p class="text-muted">Loading ${label}…</p>`);
		frappe.call({
			method: "jewellery_management.jewellery_management.dashboard.get_data",
			args,
			freeze: true,
		}).then((r) => render(r.message, label));
	}

	function render(d, label) {
		if (!d) { body.html("<p>Failed to load.</p>"); return; }
		const m = d.metal;
		body.html(`
			<h5 style="margin:6px 0 10px;">${label} · ${d.sales.count} sales · ${d.purchases.count} purchases</h5>
			<div style="display:flex;gap:10px;flex-wrap:wrap;">
				${kpi("Sales", fmt(d.sales.amount), d.sales.count + " bills", "/app/jewellery-sales-invoice")}
				${kpi("Purchases", fmt(d.purchases.amount), d.purchases.count + " bills", "/app/jewellery-purchase-invoice")}
				${kpi("Stock Value", fmt(d.stock_value), "at latest rate", "/app/query-report/Retail%20Stock%20Balance")}
				${kpi("Receivables", fmt(d.receivables), "customer dues", "/app/query-report/Customer%20Outstanding")}
				${kpi("Payables", fmt(d.payables), "supplier dues", "/app/jewellery-purchase-invoice")}
				${kpi("Active Orders", d.orders.active, fmt(d.orders.amount) + " · " + d.orders.pending_delivery + " to deliver", "/app/jewellery-order")}
				${kpi("Karigar Pending", d.karigar.jobs + " jobs", g(d.karigar.weight), "/app/jewellery-order")}
				${kpi("Old Gold", d.old_gold.pending + " lots", g(d.old_gold.fine), "/app/old-gold-receipt")}
				${kpi("Low / Out of Stock", d.low_stock.out_of_stock + " out", "lowest 5 below", "/app/query-report/HUID%20Register")}
				${kpi("Cash in Hand", fmt(d.cash), "books", "/app/query-report/General%20Ledger")}
				${kpi("Bank Balance", fmt(d.bank), "books", "/app/query-report/General%20Ledger")}
			</div>
			<div style="display:flex;gap:10px;flex-wrap:wrap;margin-top:12px;">
				<div style="border:1px solid var(--border-color);border-radius:8px;padding:12px 14px;flex:1;min-width:260px;">
					<div style="font-weight:700;margin-bottom:8px;">GOLD STOCK</div>
					<div>22K Gold <b style="float:right;">${g(m.gold_22k)}</b></div>
					<div>18K Gold <b style="float:right;">${g(m.gold_18k)}</b></div>
					<div>24K / Other <b style="float:right;">${g(m.gold_24k + m.gold_other)}</b></div>
					<hr style="margin:6px 0;">
					<div>Combined Gold <b style="float:right;">${g(m.gold_total)}</b></div>
					<div style="font-weight:700;margin:8px 0;">SILVER STOCK</div>
					<div>Silver <b style="float:right;">${g(m.silver)}</b></div>
				</div>
				<div style="border:1px solid var(--border-color);border-radius:8px;padding:12px 14px;flex:2;min-width:300px;">
					<div style="font-weight:700;margin-bottom:8px;">Sales vs Purchases</div>
					<div class="jm-chart"></div>
				</div>
			</div>
			<div style="display:flex;gap:10px;flex-wrap:wrap;margin-top:12px;">
				<div style="border:1px solid var(--border-color);border-radius:8px;padding:12px 14px;flex:1;min-width:260px;">
					<div style="font-weight:700;margin-bottom:8px;">Lowest Stock</div>
					${d.low_stock.lowest.map((r) => `<div>${frappe.utils.escape_html(r.name)} <span class="text-muted">${r.id}</span><b style="float:right;">${g(r.weight)}</b></div>`).join("") || "<span class='text-muted'>No stock movement yet.</span>"}
				</div>
				<div style="border:1px solid var(--border-color);border-radius:8px;padding:12px 14px;flex:2;min-width:300px;">
					<div style="font-weight:700;margin-bottom:8px;">Recent Activity &amp; Transactions</div>
					${d.activity.map((a) => `<div style="margin-bottom:4px;"><span class="text-muted">${a.date}</span> · ${frappe.utils.escape_html(a.text)}</div>`).join("") || "<span class='text-muted'>Nothing yet.</span>"}
				</div>
			</div>`);
		if (d.trend && d.trend.length && frappe.Chart) {
			new frappe.Chart(body.find(".jm-chart")[0], {
				data: {
					labels: d.trend.map((t) => t.date.slice(5)),
					datasets: [
						{ name: "Sales", values: d.trend.map((t) => t.sales) },
						{ name: "Purchases", values: d.trend.map((t) => t.purchases) },
					],
				},
				type: "line",
				height: 220,
				axisOptions: { xIsSeries: true },
			});
		}
	}

	page._jm_reload = () => load(page._jm_label || "This Month");
	load("This Month");
};

frappe.pages["jewellery-dashboard"].on_page_show = function (wrapper) {
	const page = wrapper.page;
	if (page && page._jm_label) {
		page._jm_reload && page._jm_reload();
	}
};
