(function () {

    const STYLE_ID = "jewellery-kanban-final-style";
    const TOOLTIP_ID = "jewellery-kanban-order-tooltip";
    const BUTTON_CLASS = "jewellery-kanban-expand-button";
    const COMPACT_CLASS = "jewellery-kanban-compact-content";
    const DETAILS_CLASS = "jewellery-kanban-details";

    let observer_started = false;


    /* =========================================================
       STYLES
       ========================================================= */

    function add_styles() {

        if (document.getElementById(STYLE_ID)) {
            return;
        }

        const style = document.createElement("style");
        style.id = STYLE_ID;

        style.textContent = `

            /* -------------------------------------------------
               CARD
            ------------------------------------------------- */

            .kanban-card-body {
                position: relative !important;
            }


            /* -------------------------------------------------
               REMOVE STANDARD FIELDS FROM OUR JEWELLERY CARD
            ------------------------------------------------- */

            .jewellery-kanban-card
            .kanban-card-doc {
                display: none !important;
            }


            /* -------------------------------------------------
               COMPACT CONTENT
            ------------------------------------------------- */

            .${COMPACT_CLASS} {
                margin-top: 0;
                padding-right: 22px;
            }

            .${COMPACT_CLASS} .jewellery-kanban-mobile {
                margin-top: 0 !important;
                margin-bottom: 1px !important;
            }

            .${COMPACT_CLASS} .jewellery-kanban-items {
                margin-top: 0 !important;
            }


            .jewellery-kanban-mobile {

                font-size: 13px;

                line-height: 1.4;

                margin-bottom: 2px;

                white-space: nowrap;

                overflow: hidden;

                text-overflow: ellipsis;
            }


            .jewellery-kanban-items {

                display: -webkit-box;

                -webkit-box-orient: vertical;

                -webkit-line-clamp: 2;

                overflow: hidden;

                white-space: pre-line;

                line-height: 1.45;

                cursor: help;

                word-break: normal;
            }


            /* -------------------------------------------------
               EXPANDED DETAILS
            ------------------------------------------------- */

            .${DETAILS_CLASS} {

                display: none;

                margin-top: 8px;

                padding-top: 8px;

                border-top: 1px solid
                    var(--border-color, rgba(128,128,128,0.20));
            }


            .jewellery-kanban-expanded
            .${DETAILS_CLASS} {

                display: block;
            }


            .jewellery-kanban-detail-row {

                display: flex;

                gap: 6px;

                margin-bottom: 4px;

                line-height: 1.4;

                font-size: 12px;
            }


            .jewellery-kanban-detail-label {

                flex: 0 0 auto;

                font-weight: 600;

                opacity: 0.75;
            }


            .jewellery-kanban-detail-value {

                min-width: 0;

                overflow-wrap: anywhere;
            }


            /* -------------------------------------------------
               EXPAND / COLLAPSE BUTTON
            ------------------------------------------------- */

            .${BUTTON_CLASS} {

                position: absolute !important;

                top: 5px !important;

                right: 5px !important;

                display: flex !important;

                align-items: center !important;

                justify-content: center !important;

                width: 17px !important;

                height: 17px !important;

                margin: 0 !important;

                padding: 0 !important;

                border: 0 !important;

                background: transparent !important;

                color: var(--text-color) !important;

                cursor: pointer !important;

                font-size: 9px !important;

                line-height: 1 !important;

                font-weight: normal !important;

                opacity: 0.70 !important;

                z-index: 30 !important;
            }


            .${BUTTON_CLASS}:hover {

                opacity: 1 !important;

                background:
                    var(--fg-hover-color) !important;

                border-radius: 4px !important;
            }


            /* -------------------------------------------------
               TOOLTIP
            ------------------------------------------------- */

            #${TOOLTIP_ID} {

                position: fixed !important;

                display: none;

                box-sizing: border-box;

                width: max-content;

                max-width: min(
                    520px,
                    calc(100vw - 24px)
                );

                max-height: calc(
                    100vh - 24px
                );

                overflow-y: auto;

                padding: 12px 14px;

                background:
                    var(--card-bg, #ffffff);

                color:
                    var(--text-color, #222222);

                border: 1px solid
                    var(--border-color, #c9c9c9);

                border-radius: 7px;

                box-shadow:
                    0 8px 30px
                    rgba(0, 0, 0, 0.28);

                font-size: 13px;

                line-height: 1.5;

                white-space: pre-line;

                overflow-wrap: anywhere;

                z-index: 999999 !important;

                pointer-events: none;
            }


            #${TOOLTIP_ID}.visible {

                display: block !important;
            }


            .jewellery-kanban-tooltip-title {

                font-weight: 700;

                margin-bottom: 5px;
            }


            .jewellery-kanban-tooltip-mobile {

                margin-bottom: 8px;

                opacity: 0.85;
            }


            .jewellery-kanban-tooltip-items {

                padding-bottom: 7px;

                margin-bottom: 7px;

                border-bottom: 1px solid
                    var(--border-color, rgba(128,128,128,0.25));

                white-space: pre-line;
            }

        `;

        document.head.appendChild(style);
    }


    /* =========================================================
       TOOLTIP
       ========================================================= */

    function get_tooltip() {

        let tooltip =
            document.getElementById(
                TOOLTIP_ID
            );

        if (tooltip) {
            return tooltip;
        }

        tooltip =
            document.createElement("div");

        tooltip.id = TOOLTIP_ID;

        document.body.appendChild(
            tooltip
        );

        return tooltip;
    }


    function hide_tooltip() {

        const tooltip =
            document.getElementById(
                TOOLTIP_ID
            );

        if (!tooltip) {
            return;
        }

        tooltip.classList.remove(
            "visible"
        );
    }


    function position_tooltip(
        tooltip,
        target
    ) {

        const rect =
            target.getBoundingClientRect();

        const margin = 8;

        let left = rect.left;

        let top =
            rect.bottom +
            margin;


        const tooltip_rect =
            tooltip.getBoundingClientRect();


        if (
            left +
            tooltip_rect.width >
            window.innerWidth -
            margin
        ) {

            left =
                window.innerWidth -
                tooltip_rect.width -
                margin;
        }


        if (left < margin) {
            left = margin;
        }


        if (
            top +
            tooltip_rect.height >
            window.innerHeight -
            margin
        ) {

            top =
                rect.top -
                tooltip_rect.height -
                margin;
        }


        if (top < margin) {
            top = margin;
        }


        tooltip.style.left =
            Math.round(left) +
            "px";

        tooltip.style.top =
            Math.round(top) +
            "px";
    }


    async function show_tooltip(
        target,
        order_name
    ) {

        if (!order_name) {
            return;
        }


        const tooltip =
            get_tooltip();


        let result;


        try {

            result =
                await frappe.db.get_value(
                    "Jewellery Order",
                    order_name,
                    [
                        "customer",
                        "contact_number",
                        "item_summary",
                        "order_date",
                        "delivery_date",
                        "grand_total",
                        "balance_amount"
                    ]
                );

        } catch (error) {

            console.warn(
                "Unable to load Jewellery Order tooltip:",
                error
            );

            return;
        }


        const data =
            result &&
            result.message
                ? result.message
                : {};


        const customer =
            data.customer || order_name;


        const mobile =
            data.contact_number || "";


        const item_summary =
            data.item_summary || "";


        const order_date =
            data.order_date || "";


        const delivery_date =
            data.delivery_date || "";


        const grand_total =
            data.grand_total !== undefined &&
            data.grand_total !== null
                ? data.grand_total
                : "";


        const balance_amount =
            data.balance_amount !== undefined &&
            data.balance_amount !== null
                ? data.balance_amount
                : "";


        /*
         * Construct DOM nodes instead of inserting
         * unescaped database values as HTML.
         */

        tooltip.innerHTML = "";


        const title =
            document.createElement("div");

        title.className =
            "jewellery-kanban-tooltip-title";

        title.textContent =
            customer;

        tooltip.appendChild(
            title
        );


        if (mobile) {

            const mobile_div =
                document.createElement("div");

            mobile_div.className =
                "jewellery-kanban-tooltip-mobile";

            mobile_div.textContent =
                "Mobile: " + mobile;

            tooltip.appendChild(
                mobile_div
            );
        }


        if (item_summary) {

            const items =
                document.createElement("div");

            items.className =
                "jewellery-kanban-tooltip-items";

            items.textContent =
                item_summary;

            tooltip.appendChild(
                items
            );
        }


        const add_detail =
            function (
                label,
                value
            ) {

                if (
                    value === "" ||
                    value === null ||
                    value === undefined
                ) {
                    return;
                }


                const row =
                    document.createElement("div");

                row.className =
                    "jewellery-kanban-detail-row";


                const label_el =
                    document.createElement("span");

                label_el.className =
                    "jewellery-kanban-detail-label";

                label_el.textContent =
                    label + ":";


                const value_el =
                    document.createElement("span");

                value_el.className =
                    "jewellery-kanban-detail-value";

                value_el.textContent =
                    String(value);


                row.appendChild(
                    label_el
                );

                row.appendChild(
                    value_el
                );

                tooltip.appendChild(
                    row
                );
            };


        add_detail(
            "Order Date",
            order_date
        );

        add_detail(
            "Delivery Date",
            delivery_date
        );

        add_detail(
            "Grand Total",
            format_currency(
                grand_total
            )
        );

        add_detail(
            "Balance Amount",
            format_currency(
                balance_amount
            )
        );


        tooltip.classList.add(
            "visible"
        );


        position_tooltip(
            tooltip,
            target
        );
    }


    /* =========================================================
       TOOLTIP BINDING
       ========================================================= */

    function bind_tooltip(
        $wrapper,
        order_name
    ) {

        const $items =
            $wrapper.find(
                ".jewellery-kanban-items"
            );


        if (!$items.length) {
            return;
        }


        if (
            $items.attr(
                "data-tooltip-bound"
            ) === "1"
        ) {
            return;
        }


        $items.attr(
            "data-tooltip-bound",
            "1"
        );


        $items.on(
            "mouseenter",
            function () {

                show_tooltip(
                    this,
                    order_name
                );

            }
        );


        $items.on(
            "mouseleave",
            function () {

                hide_tooltip();

            }
        );
    }


    /* =========================================================
       EXPAND / COLLAPSE
       ========================================================= */

    function add_expand_button(
        $wrapper
    ) {

        if (
            $wrapper.find(
                "." + BUTTON_CLASS
            ).length
        ) {
            return;
        }


        const $body =
            $wrapper.find(
                ".kanban-card-body"
            );


        if (!$body.length) {
            return;
        }


        const $button =
            $(
                `<button
                    type="button"
                    class="${BUTTON_CLASS}"
                    title="Show more"
                    aria-label="Show more">
                    ▼
                </button>`
            );


        $body.append(
            $button
        );


        $button.on(
            "click",
            function (event) {

                event.preventDefault();

                event.stopPropagation();


                const expanded =
                    $wrapper.hasClass(
                        "jewellery-kanban-expanded"
                    );


                if (expanded) {

                    $wrapper
                        .removeClass(
                            "jewellery-kanban-expanded"
                        )
                        .addClass(
                            "jewellery-kanban-collapsed"
                        );


                    $button
                        .text("▼")
                        .attr(
                            "title",
                            "Show more"
                        )
                        .attr(
                            "aria-label",
                            "Show more"
                        );

                } else {

                    $wrapper
                        .removeClass(
                            "jewellery-kanban-collapsed"
                        )
                        .addClass(
                            "jewellery-kanban-expanded"
                        );


                    $button
                        .text("▲")
                        .attr(
                            "title",
                            "Show less"
                        )
                        .attr(
                            "aria-label",
                            "Show less"
                        );
                }

            }
        );
    }


    /* =========================================================
       CREATE COMPACT CARD CONTENT
       ========================================================= */

    function prepare_card(
        $wrapper
    ) {

        if (
            !$wrapper ||
            !$wrapper.length
        ) {
            return;
        }


        /*
         * We only customize Jewellery Order cards.
         *
         * Kanban card title is already the customer name.
         */

        if (
            $wrapper.data(
                "jewellery-prepared"
            )
        ) {
            return;
        }


        $wrapper
            .data(
                "jewellery-prepared",
                true
            )
            .addClass(
                "jewellery-kanban-card"
            )
            .addClass(
                "jewellery-kanban-collapsed"
            );


        /*
         * Remove Frappe's standard line break between
         * the card title and our compact content.
         */

        $wrapper
            .find(".kanban-title-area > br")
            .remove();


        /*
         * Recover the document name.
         */

        const encoded_name =
            $wrapper.attr(
                "data-name"
            ) || "";


        let order_name = "";

        try {

            order_name =
                decodeURIComponent(
                    encoded_name
                );

        } catch (error) {

            order_name =
                encoded_name;

        }


        /*
         * Existing standard title is the customer name.
         * We remove standard field content and replace it
         * with our compact presentation.
         */

        const $doc_content =
            $wrapper.find(
                ".kanban-card-doc"
            );


        $doc_content.empty();


        const $title_area =
            $wrapper.find(
                ".kanban-title-area"
            );


        if (!$title_area.length) {
            return;
        }


        /*
         * Remove our content if it somehow exists
         * from a previous render.
         */

        $title_area.find(
            "." + COMPACT_CLASS
        ).remove();


        const $compact =
            $(
                `<div class="${COMPACT_CLASS}">
                    <div class="jewellery-kanban-mobile"></div>
                    <div class="jewellery-kanban-items"></div>
                    <div class="${DETAILS_CLASS}"></div>
                </div>`
            );


        $title_area.append(
            $compact
        );


        /*
         * Fetch only the compact information.
         */

        frappe.db.get_value(
            "Jewellery Order",
            order_name,
            [
                "contact_number",
                "item_summary",
                "order_date",
                "delivery_date",
                "grand_total",
                "balance_amount"
            ]
        ).then(function (response) {

            const data =
                response &&
                response.message
                    ? response.message
                    : {};


            const mobile =
                data.contact_number || "";


            const summary =
                data.item_summary || "";


            const order_date =
                data.order_date || "";


            const delivery_date =
                data.delivery_date || "";


            const grand_total =
                data.grand_total !== undefined &&
                data.grand_total !== null
                    ? data.grand_total
                    : "";


            const balance_amount =
                data.balance_amount !== undefined &&
                data.balance_amount !== null
                    ? data.balance_amount
                    : "";


            const $mobile =
                $compact.find(
                    ".jewellery-kanban-mobile"
                );


            const $items =
                $compact.find(
                    ".jewellery-kanban-items"
                );


            const $details =
                $compact.find(
                    "." + DETAILS_CLASS
                );


            /*
             * Mobile line only exists when there is
             * actually a mobile/contact number.
             */

            if (mobile) {

                $mobile
                    .text(mobile)
                    .show();

            } else {

                $mobile
                    .text("")
                    .hide();
            }


            /*
             * Item Summary has no label.
             */

            $items.text(
                summary
            );


            /*
             * Expanded details.
             */

            $details.empty();


            add_detail_row(
                $details,
                "Order Date",
                order_date
            );

            add_detail_row(
                $details,
                "Delivery Date",
                delivery_date
            );

            add_detail_row(
                $details,
                "Grand Total",
                format_currency(
                    grand_total
                )
            );

            add_detail_row(
                $details,
                "Balance Amount",
                format_currency(
                    balance_amount
                )
            );


            bind_tooltip(
                $wrapper,
                order_name
            );

        }).catch(function (error) {

            console.warn(
                "Jewellery Kanban compact data load failed:",
                error
            );

        });


        add_expand_button(
            $wrapper
        );
    }


    /* =========================================================
       DETAIL ROW
       ========================================================= */

    function add_detail_row(
        $container,
        label,
        value
    ) {

        if (
            value === "" ||
            value === null ||
            value === undefined
        ) {
            return;
        }


        const $row =
            $(
                `<div class="jewellery-kanban-detail-row">
                    <span class="jewellery-kanban-detail-label"></span>
                    <span class="jewellery-kanban-detail-value"></span>
                </div>`
            );


        $row.find(
            ".jewellery-kanban-detail-label"
        ).text(
            label + ":"
        );


        $row.find(
            ".jewellery-kanban-detail-value"
        ).text(
            String(value)
        );


        $container.append(
            $row
        );
    }


    /* =========================================================
       SCAN CARDS
       ========================================================= */

    function scan_cards() {

        add_styles();


        $(
            ".kanban-card-wrapper"
        ).each(function () {

            prepare_card(
                $(this)
            );

        });
    }


    /* =========================================================
       MUTATION OBSERVER
       ========================================================= */

    function start_observer() {

        if (observer_started) {
            return;
        }


        observer_started = true;


        const observer =
            new MutationObserver(
                function (mutations) {

                    let changed =
                        false;


                    for (
                        const mutation
                        of mutations
                    ) {

                        if (
                            mutation.addedNodes &&
                            mutation.addedNodes.length
                        ) {

                            changed = true;

                            break;
                        }

                    }


                    if (changed) {

                        setTimeout(
                            scan_cards,
                            0
                        );

                    }

                }
            );


        observer.observe(
            document.body,
            {
                childList: true,
                subtree: true
            }
        );
    }


    /* =========================================================
       START
       ========================================================= */

    function start() {

        add_styles();

        start_observer();

        scan_cards();


        setTimeout(
            scan_cards,
            300
        );

        setTimeout(
            scan_cards,
            1000
        );

        setTimeout(
            scan_cards,
            2000
        );
    }


    if (
        document.readyState ===
        "loading"
    ) {

        document.addEventListener(
            "DOMContentLoaded",
            start
        );

    } else {

        start();

    }

})();
