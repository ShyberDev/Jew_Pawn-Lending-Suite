app_name = "jewellery_management"
app_title = "Jewellery Management"
app_publisher = "Sri Sai Krishna Jewellery"
app_description = "Jewellery Management System for Sri Sai Krishna Jewellery"
app_email = "benwolf449@gmail.com"
app_license = "mit"

use_json_request_body = True

add_to_apps_screen = [
    {
        "name": "jewellery_management",
        "logo": "/assets/jewellery_management/images/logo.svg",
        "title": "Sri Sai Krishna Jewellery",
        "route": "/app/jewellery-dashboard",
        "sequence_id": 1,
    }
]

app_include_js = [
    "/assets/jewellery_management/js/jewellery_kanban.js"
]

after_migrate = "jewellery_management.jewellery_management.stock_hooks.ensure_kanban_board"

boot_session = "jewellery_management.jewellery_management.calculations.add_boot_settings"

doc_events = {
    "Jewellery Purchase Invoice": {
        "validate": [
            "jewellery_management.jewellery_management.calculations.recalc_purchase_invoice",
            "jewellery_management.jewellery_management.stock_hooks.validate_return",
        ],
        "on_submit": "jewellery_management.jewellery_management.stock_hooks.create_purchase_stock_transactions",
        "on_cancel": "jewellery_management.jewellery_management.stock_hooks.reverse_stock_transactions",
    },

    "Jewellery Sales Invoice": {
        "validate": [
            "jewellery_management.jewellery_management.calculations.recalc_sales_invoice",
            "jewellery_management.jewellery_management.stock_hooks.validate_return",
        ],
        "on_submit": "jewellery_management.jewellery_management.stock_hooks.create_sales_stock_transactions",
        "on_cancel": "jewellery_management.jewellery_management.stock_hooks.reverse_stock_transactions",
    },

    "Jewellery Opening Stock": {
        "validate": "jewellery_management.jewellery_management.calculations.recalc_opening_stock",
        "on_submit": "jewellery_management.jewellery_management.stock_hooks.create_opening_stock_transactions",
        "on_cancel": "jewellery_management.jewellery_management.stock_hooks.reverse_stock_transactions",
    },

    "Jewellery Order": {
        "validate": "jewellery_management.jewellery_management.calculations.recalc_order",
        "on_trash": [
            "jewellery_management.jewellery_management.stock_hooks.remove_order_from_kanban",
            "jewellery_management.jewellery_management.stock_hooks.reverse_stock_transactions",
        ],
    },

    "Worker Settlement": {
        "validate": "jewellery_management.jewellery_management.settlement.validate_settlement",
        "on_submit": "jewellery_management.jewellery_management.settlement.validate_settlement",
    },

    "Old Gold Receipt": {
        "validate": "jewellery_management.jewellery_management.old_gold.validate_receipt",
        "on_submit": "jewellery_management.jewellery_management.old_gold.validate_receipt",
    },

    "Old Gold Melt": {
        "validate": "jewellery_management.jewellery_management.old_gold.validate_melt",
        "before_submit": "jewellery_management.jewellery_management.old_gold.validate_melt",
    },

    "Jewellery Repair": {
        "validate": "jewellery_management.jewellery_management.workshop.validate_repair",
    },
}

export_python_type_annotations = True
require_type_annotated_api_methods = True

fixtures = [
    {
        "dt": "DocType",
        "filters": [["module", "=", "Jewellery"]],
    },
    {
        "dt": "Client Script",
        "filters": [
            [
                "dt",
                "in",
                [
                    "Jewellery Order",
                    "Jewellery Opening Stock",
                    "Jewellery Sales Invoice",
                    "Jewellery Purchase Invoice",
                    "Retail Stock Item",
                ],
            ]
        ],
    },
    {"dt": "Report", "filters": [["module", "=", "Jewellery"]]},
    {"dt": "Print Format", "filters": [["module", "=", "Jewellery"]]},
    {
        "dt": "Workflow",
        "filters": [["document_type", "like", "Jewellery%"]],
    },
    {
        "dt": "Custom Field",
        "filters": [["dt", "like", "Jewellery%"]],
    },
    {
        "dt": "Workspace",
        "filters": [["module", "=", "Jewellery Management"]],
    },
]
