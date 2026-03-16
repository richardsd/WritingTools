import os
import sys

from aiprovider import AIProvider, CodexProvider
from PySide6 import QtCore, QtWidgets
from PySide6.QtGui import QImage
from PySide6.QtWidgets import QHBoxLayout, QRadioButton, QScrollArea

from active_app import get_active_app_context
from app_profile import AppMatcher, AppProfile, FormattingPreset
from app_profile_service import AppProfileService
from history_manager import HistoryManager
from ui.AutostartManager import AutostartManager
from ui.UIUtils import UIUtils, colorMode

_ = lambda x: x

class SettingsWindow(QtWidgets.QWidget):
    """
    The settings window for the application.
    Now with scrolling support for better usability on smaller screens.
    """
    close_signal = QtCore.Signal()

    def __init__(self, app, providers_only=False):
        super().__init__()
        self.app = app
        self.current_provider_layout = None
        self.providers_only = providers_only
        self.gradient_radio = None
        self.plain_radio = None
        self.provider_dropdown = None
        self.provider_container = None
        self.autostart_checkbox = None
        self.shortcut_input = None
        self.init_ui()
        self.retranslate_ui()


    def retranslate_ui(self):
        self.setWindowTitle(_("Settings"))

    def init_provider_ui(self, provider: AIProvider, layout):
        """
        Initialize the user interface for the provider, including logo, name, description and all settings.
        """
        if self.current_provider_layout:
            self.current_provider_layout.setParent(None)
            UIUtils.clear_layout(self.current_provider_layout)
            self.current_provider_layout.deleteLater()

        self.current_provider_layout = QtWidgets.QVBoxLayout()

        # Create a horizontal layout for the logo and provider name
        provider_header_layout = QtWidgets.QHBoxLayout()
        provider_header_layout.setSpacing(10)
        provider_header_layout.setAlignment(QtCore.Qt.AlignmentFlag.AlignCenter)

        if provider.logo:
            logo_path = os.path.join(os.path.dirname(sys.argv[0]), 'icons', f"provider_{provider.logo}.png")
            if os.path.exists(logo_path):
                targetPixmap = UIUtils.resize_and_round_image(QImage(logo_path), 30, 15)
                logo_label = QtWidgets.QLabel()
                logo_label.setPixmap(targetPixmap)
                logo_label.setAlignment(QtCore.Qt.AlignmentFlag.AlignVCenter)
                provider_header_layout.addWidget(logo_label)

        provider_name_label = QtWidgets.QLabel(provider.provider_name)
        provider_name_label.setStyleSheet(f"font-size: 18px; font-weight: bold; color: {'#ffffff' if colorMode == 'dark' else '#333333'};")
        provider_name_label.setAlignment(QtCore.Qt.AlignmentFlag.AlignVCenter)
        provider_header_layout.addWidget(provider_name_label)

        self.current_provider_layout.addLayout(provider_header_layout)

        if provider.description:
            description_label = QtWidgets.QLabel(provider.description)
            description_label.setStyleSheet(f"font-size: 16px; color: {'#ffffff' if colorMode == 'dark' else '#333333'}; text-align: center;")
            description_label.setWordWrap(True)
            self.current_provider_layout.addWidget(description_label)

        if hasattr(provider, 'ollama_button_text'):
            # Create container for buttons
            button_layout = QtWidgets.QHBoxLayout()
            
            # Add Ollama setup button
            ollama_button = QtWidgets.QPushButton(provider.ollama_button_text)
            ollama_button.setStyleSheet(f"""
                QPushButton {{
                    background-color: {'#4CAF50' if colorMode == 'dark' else '#008CBA'};
                    color: white;
                    padding: 10px;
                    font-size: 16px;
                    border: none;
                    border-radius: 5px;
                }}
                QPushButton:hover {{
                    background-color: {'#45a049' if colorMode == 'dark' else '#007095'};
                }}
            """)
            ollama_button.clicked.connect(provider.ollama_button_action)
            button_layout.addWidget(ollama_button)
            
            # Add original button
            main_button = QtWidgets.QPushButton(provider.button_text)
            main_button.setStyleSheet(f"""
                QPushButton {{
                    background-color: {'#4CAF50' if colorMode == 'dark' else '#008CBA'};
                    color: white;
                    padding: 10px;
                    font-size: 16px;
                    border: none;
                    border-radius: 5px;
                }}
                QPushButton:hover {{
                    background-color: {'#45a049' if colorMode == 'dark' else '#007095'};
                }}
            """)
            main_button.clicked.connect(provider.button_action)
            button_layout.addWidget(main_button)
            
            self.current_provider_layout.addLayout(button_layout)
        else:
            # Original single button logic
            if provider.button_text:
                button = QtWidgets.QPushButton(provider.button_text)
                button.setStyleSheet(f"""
                    QPushButton {{
                        background-color: {'#4CAF50' if colorMode == 'dark' else '#008CBA'};
                        color: white;
                        padding: 10px;
                        font-size: 16px;
                        border: none;
                        border-radius: 5px;
                    }}
                    QPushButton:hover {{
                        background-color: {'#45a049' if colorMode == 'dark' else '#007095'};
                    }}
                """)
                button.clicked.connect(provider.button_action)
                self.current_provider_layout.addWidget(button, alignment=QtCore.Qt.AlignmentFlag.AlignCenter)

        # Initialize config if needed
        if "providers" not in self.app.config:
            self.app.config["providers"] = {}
        if provider.provider_name not in self.app.config["providers"]:
            self.app.config["providers"][provider.provider_name] = {}

        # Add provider settings
        for setting in provider.settings:
            setting.set_value(self.app.config["providers"][provider.provider_name].get(setting.name, setting.default_value))
            setting.render_to_layout(self.current_provider_layout)

        layout.addLayout(self.current_provider_layout)

    def init_ui(self):
        """
        Initialize the user interface for the settings window.
        Uses a QTabWidget with Settings, Profiles, and History tabs.
        """
        self.setWindowTitle(_('Settings'))
        self.setMinimumWidth(750)
        self.setFixedWidth(750)

        UIUtils.setup_window_and_layout(self)
        main_layout = QtWidgets.QVBoxLayout(self.background)
        main_layout.setContentsMargins(0, 0, 0, 0)
        main_layout.setSpacing(10)

        # ── Tab Widget ───────────────────────────────────────────
        self.tab_widget = QtWidgets.QTabWidget()
        tab_style = f"""
            QTabWidget::pane {{
                border: 1px solid {'#555' if colorMode == 'dark' else '#ccc'};
                background: transparent;
            }}
            QTabBar::tab {{
                padding: 8px 20px;
                font-size: 14px;
                background: {'#333' if colorMode == 'dark' else '#e8e8e8'};
                color: {'#ccc' if colorMode == 'dark' else '#555'};
                border: 1px solid {'#555' if colorMode == 'dark' else '#ccc'};
                border-bottom: none;
                border-top-left-radius: 6px;
                border-top-right-radius: 6px;
                margin-right: 2px;
            }}
            QTabBar::tab:selected {{
                background: {'#444' if colorMode == 'dark' else '#fff'};
                color: {'#fff' if colorMode == 'dark' else '#333'};
            }}
        """
        self.tab_widget.setStyleSheet(tab_style)

        if not self.providers_only:
            settings_tab = self._build_settings_tab()
            self.tab_widget.addTab(settings_tab, _("Settings"))

            profiles_tab = self._build_profiles_tab()
            self.tab_widget.addTab(profiles_tab, _("Profiles"))

            history_tab = self._build_history_tab()
            self.tab_widget.addTab(history_tab, _("History"))
        else:
            settings_tab = self._build_settings_tab()
            self.tab_widget.addTab(settings_tab, _("AI Provider"))

        main_layout.addWidget(self.tab_widget)

        # ── Bottom bar ───────────────────────────────────────────
        bottom_container = QtWidgets.QWidget()
        bottom_container.setStyleSheet("background: transparent;")
        bottom_layout = QtWidgets.QVBoxLayout(bottom_container)
        bottom_layout.setContentsMargins(30, 0, 30, 20)
        bottom_layout.setSpacing(10)

        save_button = QtWidgets.QPushButton(_("Finish AI Setup") if self.providers_only else _("Save"))
        save_button.setStyleSheet("""
            QPushButton {
                background-color: #4CAF50;
                color: white;
                padding: 10px;
                font-size: 16px;
                border: none;
                border-radius: 5px;
            }
            QPushButton:hover {
                background-color: #45a049;
            }
        """)
        save_button.clicked.connect(self.save_settings)
        bottom_layout.addWidget(save_button)

        if not self.providers_only:
            restart_text = "<p style='text-align: center;'>" + \
                _("Please restart Writing Tools for changes to take effect.") + "</p>"
            restart_notice = QtWidgets.QLabel(restart_text)
            restart_notice.setStyleSheet(f"font-size: 15px; color: {'#cccccc' if colorMode == 'dark' else '#555555'}; font-style: italic;")
            restart_notice.setWordWrap(True)
            bottom_layout.addWidget(restart_notice)

        main_layout.addWidget(bottom_container)

        screen = QtWidgets.QApplication.primaryScreen().geometry()
        max_height = int(screen.height() * 0.85)
        desired_height = min(720, max_height)
        self.resize(750, desired_height)

    # ══════════════════════════════════════════════════════════════
    #  Settings Tab
    # ══════════════════════════════════════════════════════════════

    def _build_settings_tab(self):
        scroll_area = QScrollArea()
        scroll_area.setWidgetResizable(True)
        scroll_area.setFrameShape(QtWidgets.QFrame.Shape.NoFrame)
        scroll_area.setHorizontalScrollBarPolicy(QtCore.Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        scroll_area.setStyleSheet(self._scroll_area_style())

        scroll_content = QtWidgets.QWidget()
        scroll_content.setStyleSheet("background: transparent;")
        content_layout = QtWidgets.QVBoxLayout(scroll_content)
        content_layout.setContentsMargins(30, 20, 30, 20)
        content_layout.setSpacing(20)

        if not self.providers_only:
            if AutostartManager.get_startup_path():
                self.autostart_checkbox = QtWidgets.QCheckBox(_("Start on Boot"))
                self.autostart_checkbox.setStyleSheet(f"font-size: 16px; color: {'#ffffff' if colorMode == 'dark' else '#333333'};")
                self.autostart_checkbox.setChecked(AutostartManager.check_autostart())
                self.autostart_checkbox.stateChanged.connect(self.toggle_autostart)
                content_layout.addWidget(self.autostart_checkbox)

            shortcut_label = QtWidgets.QLabel(_("Shortcut Key:"))
            shortcut_label.setStyleSheet(f"font-size: 16px; color: {'#ffffff' if colorMode == 'dark' else '#333333'};")
            content_layout.addWidget(shortcut_label)

            self.shortcut_input = QtWidgets.QLineEdit(self.app.config.get('shortcut', 'ctrl+space'))
            self.shortcut_input.setStyleSheet(self._input_style())
            content_layout.addWidget(self.shortcut_input)

            theme_label = QtWidgets.QLabel(_("Background Theme:"))
            theme_label.setStyleSheet(f"font-size: 16px; color: {'#ffffff' if colorMode == 'dark' else '#333333'};")
            content_layout.addWidget(theme_label)

            theme_layout = QHBoxLayout()
            self.gradient_radio = QRadioButton(_("Blurry Gradient"))
            self.plain_radio = QRadioButton(_("Plain"))
            self.gradient_radio.setStyleSheet(f"color: {'#ffffff' if colorMode == 'dark' else '#333333'};")
            self.plain_radio.setStyleSheet(f"color: {'#ffffff' if colorMode == 'dark' else '#333333'};")
            current_theme = self.app.config.get('theme', 'gradient')
            self.gradient_radio.setChecked(current_theme == 'gradient')
            self.plain_radio.setChecked(current_theme == 'plain')
            theme_layout.addWidget(self.gradient_radio)
            theme_layout.addWidget(self.plain_radio)
            content_layout.addLayout(theme_layout)

            # History toggle
            self.history_checkbox = QtWidgets.QCheckBox(_("Enable Command History"))
            self.history_checkbox.setStyleSheet(f"font-size: 16px; color: {'#ffffff' if colorMode == 'dark' else '#333333'};")
            self.history_checkbox.setChecked(self.app.config.get('is_history_enabled', True))
            content_layout.addWidget(self.history_checkbox)

            line = QtWidgets.QFrame()
            line.setFrameShape(QtWidgets.QFrame.Shape.HLine)
            line.setFrameShadow(QtWidgets.QFrame.Shadow.Sunken)
            content_layout.addWidget(line)

        # Provider selection
        provider_label = QtWidgets.QLabel(_("Choose AI Provider:"))
        provider_label.setStyleSheet(f"font-size: 16px; color: {'#ffffff' if colorMode == 'dark' else '#333333'};")
        content_layout.addWidget(provider_label)

        self.provider_dropdown = QtWidgets.QComboBox()
        self.provider_dropdown.setStyleSheet(self._dropdown_style())
        self.provider_dropdown.setInsertPolicy(QtWidgets.QComboBox.InsertPolicy.NoInsert)

        current_provider = self.app.config.get('provider', self.app.providers[0].provider_name)
        for provider in self.app.providers:
            self.provider_dropdown.addItem(provider.provider_name)
        self.provider_dropdown.setCurrentIndex(self.provider_dropdown.findText(current_provider))
        content_layout.addWidget(self.provider_dropdown)

        line2 = QtWidgets.QFrame()
        line2.setFrameShape(QtWidgets.QFrame.Shape.HLine)
        line2.setFrameShadow(QtWidgets.QFrame.Shadow.Sunken)
        content_layout.addWidget(line2)

        self.provider_container = QtWidgets.QVBoxLayout()
        content_layout.addLayout(self.provider_container)

        provider_instance = self.app.providers[self.provider_dropdown.currentIndex()]
        self.init_provider_ui(provider_instance, self.provider_container)

        self.provider_dropdown.currentIndexChanged.connect(
            lambda: self.init_provider_ui(self.app.providers[self.provider_dropdown.currentIndex()], self.provider_container)
        )

        # Codex OAuth buttons
        self.codex_oauth_container = QtWidgets.QWidget()
        self.codex_oauth_container.setStyleSheet("background: transparent;")
        codex_layout = QtWidgets.QVBoxLayout(self.codex_oauth_container)
        codex_layout.setContentsMargins(0, 10, 0, 0)

        self.codex_sign_in_button = QtWidgets.QPushButton(_("Sign in with ChatGPT"))
        self.codex_sign_in_button.setStyleSheet(self._green_button_style())
        self.codex_sign_in_button.clicked.connect(self._on_codex_sign_in)
        codex_layout.addWidget(self.codex_sign_in_button)

        self.codex_sign_out_button = QtWidgets.QPushButton(_("Sign Out"))
        self.codex_sign_out_button.setStyleSheet(self._red_button_style())
        self.codex_sign_out_button.clicked.connect(self._on_codex_sign_out)
        codex_layout.addWidget(self.codex_sign_out_button)

        self.codex_status_label = QtWidgets.QLabel("")
        self.codex_status_label.setStyleSheet(f"font-size: 14px; color: {'#aaa' if colorMode == 'dark' else '#555'};")
        codex_layout.addWidget(self.codex_status_label)

        content_layout.addWidget(self.codex_oauth_container)

        self.provider_dropdown.currentIndexChanged.connect(self._update_codex_ui)
        self._update_codex_ui()

        scroll_area.setWidget(scroll_content)
        return scroll_area

    # ══════════════════════════════════════════════════════════════
    #  Profiles Tab
    # ══════════════════════════════════════════════════════════════

    def _build_profiles_tab(self):
        widget = QtWidgets.QWidget()
        widget.setStyleSheet("background: transparent;")
        layout = QHBoxLayout(widget)
        layout.setContentsMargins(10, 10, 10, 10)
        layout.setSpacing(10)

        # Left panel — profile list
        left = QtWidgets.QVBoxLayout()
        self.profile_list = QtWidgets.QListWidget()
        self.profile_list.setStyleSheet(self._list_widget_style())
        self.profile_list.currentRowChanged.connect(self._on_profile_selected)
        left.addWidget(self.profile_list)

        btn_row = QHBoxLayout()
        add_btn = QtWidgets.QPushButton("+")
        add_btn.setFixedWidth(40)
        add_btn.setStyleSheet(self._green_button_style())
        add_btn.clicked.connect(self._add_profile)
        btn_row.addWidget(add_btn)

        remove_btn = QtWidgets.QPushButton("\u2212")
        remove_btn.setFixedWidth(40)
        remove_btn.setStyleSheet(self._red_button_style())
        remove_btn.clicked.connect(self._remove_profile)
        btn_row.addWidget(remove_btn)
        btn_row.addStretch()
        left.addLayout(btn_row)

        left_widget = QtWidgets.QWidget()
        left_widget.setLayout(left)
        left_widget.setFixedWidth(200)

        # Right panel — profile editor
        right_scroll = QScrollArea()
        right_scroll.setWidgetResizable(True)
        right_scroll.setFrameShape(QtWidgets.QFrame.Shape.NoFrame)
        right_scroll.setStyleSheet(self._scroll_area_style())

        self.profile_editor_widget = QtWidgets.QWidget()
        self.profile_editor_widget.setStyleSheet("background: transparent;")
        self.profile_editor_layout = QtWidgets.QVBoxLayout(self.profile_editor_widget)
        self.profile_editor_layout.setContentsMargins(10, 10, 10, 10)
        self.profile_editor_layout.setSpacing(12)

        ph = QtWidgets.QLabel(_("Select a profile to edit"))
        ph.setStyleSheet(f"font-size: 14px; color: {'#888' if colorMode == 'dark' else '#999'};")
        ph.setAlignment(QtCore.Qt.AlignmentFlag.AlignCenter)
        self.profile_editor_layout.addWidget(ph)

        right_scroll.setWidget(self.profile_editor_widget)

        layout.addWidget(left_widget)
        layout.addWidget(right_scroll, 1)

        self._refresh_profile_list()
        return widget

    def _refresh_profile_list(self):
        self.profile_list.clear()
        svc = AppProfileService.shared()
        for p in svc.profiles:
            label = p.name if p.is_enabled else f"[off] {p.name}"
            self.profile_list.addItem(label)

    def _on_profile_selected(self, row):
        svc = AppProfileService.shared()
        if row < 0 or row >= len(svc.profiles):
            return
        profile = svc.profiles[row]
        self._build_profile_editor(profile)

    def _build_profile_editor(self, profile: AppProfile):
        UIUtils.clear_layout(self.profile_editor_layout)

        lbl_color = f"color: {'#fff' if colorMode == 'dark' else '#333'};"

        name_label = QtWidgets.QLabel(_("Profile Name:"))
        name_label.setStyleSheet(f"font-size: 14px; {lbl_color}")
        self.profile_editor_layout.addWidget(name_label)
        name_input = QtWidgets.QLineEdit(profile.name)
        name_input.setStyleSheet(self._input_style())
        name_input.setObjectName("profile_name")
        self.profile_editor_layout.addWidget(name_input)

        enabled_cb = QtWidgets.QCheckBox(_("Enabled"))
        enabled_cb.setStyleSheet(f"font-size: 14px; {lbl_color}")
        enabled_cb.setChecked(profile.is_enabled)
        enabled_cb.setObjectName("profile_enabled")
        self.profile_editor_layout.addWidget(enabled_cb)

        preset_label = QtWidgets.QLabel(_("Formatting Preset:"))
        preset_label.setStyleSheet(f"font-size: 14px; {lbl_color}")
        self.profile_editor_layout.addWidget(preset_label)
        preset_dropdown = QtWidgets.QComboBox()
        preset_dropdown.setStyleSheet(self._dropdown_style())
        preset_dropdown.setObjectName("profile_preset")
        for fp in FormattingPreset:
            preset_dropdown.addItem(fp.display_name, fp.value)
        preset_dropdown.setCurrentIndex(preset_dropdown.findData(profile.formatting_preset.value))
        self.profile_editor_layout.addWidget(preset_dropdown)

        add_label = QtWidgets.QLabel(_("Additional Instructions:"))
        add_label.setStyleSheet(f"font-size: 14px; {lbl_color}")
        self.profile_editor_layout.addWidget(add_label)
        add_text = QtWidgets.QPlainTextEdit(profile.additional_instructions)
        add_text.setStyleSheet(self._input_style())
        add_text.setFixedHeight(80)
        add_text.setObjectName("profile_additional")
        self.profile_editor_layout.addWidget(add_text)

        matchers_label = QtWidgets.QLabel(_("App Matchers:"))
        matchers_label.setStyleSheet(f"font-size: 14px; font-weight: bold; {lbl_color}")
        self.profile_editor_layout.addWidget(matchers_label)

        self._matcher_rows = []
        for matcher in profile.matchers:
            self._add_matcher_row(matcher)

        add_matcher_btn = QtWidgets.QPushButton(_("+ Add Matcher"))
        add_matcher_btn.setStyleSheet(self._green_button_style())
        add_matcher_btn.clicked.connect(lambda: self._add_matcher_row(AppMatcher("app_name_contains", "")))
        self.profile_editor_layout.addWidget(add_matcher_btn)

        use_active_btn = QtWidgets.QPushButton(_("Use Active App"))
        use_active_btn.setToolTip(_("Add a matcher from the currently focused app"))
        use_active_btn.setStyleSheet(self._green_button_style())
        use_active_btn.clicked.connect(self._use_active_app_for_matcher)
        self.profile_editor_layout.addWidget(use_active_btn)

        save_btn = QtWidgets.QPushButton(_("Save Profile"))
        save_btn.setStyleSheet(self._green_button_style())
        save_btn.clicked.connect(lambda: self._save_current_profile(profile.id))
        self.profile_editor_layout.addWidget(save_btn)

        self.profile_editor_layout.addStretch()

    def _add_matcher_row(self, matcher: AppMatcher):
        row_widget = QtWidgets.QWidget()
        row_widget.setStyleSheet("background: transparent;")
        row_layout = QHBoxLayout(row_widget)
        row_layout.setContentsMargins(0, 0, 0, 0)

        type_combo = QtWidgets.QComboBox()
        type_combo.setStyleSheet(self._dropdown_style())
        type_combo.addItem(_("App Name Contains"), "app_name_contains")
        type_combo.addItem(_("Process Name Equals"), "process_name_equals")
        type_combo.setCurrentIndex(type_combo.findData(matcher.match_type))
        row_layout.addWidget(type_combo)

        value_input = QtWidgets.QLineEdit(matcher.value)
        value_input.setStyleSheet(self._input_style())
        value_input.setPlaceholderText(_("e.g. Code, Obsidian"))
        row_layout.addWidget(value_input)

        remove_btn = QtWidgets.QPushButton("\u00d7")
        remove_btn.setFixedWidth(30)
        remove_btn.setStyleSheet(self._red_button_style())
        remove_btn.clicked.connect(lambda: self._remove_matcher_row(row_widget))
        row_layout.addWidget(remove_btn)

        self.profile_editor_layout.addWidget(row_widget)
        self._matcher_rows.append(row_widget)

    def _remove_matcher_row(self, row_widget):
        if row_widget in self._matcher_rows:
            self._matcher_rows.remove(row_widget)
        row_widget.setParent(None)
        row_widget.deleteLater()

    def _use_active_app_for_matcher(self):
        ctx = get_active_app_context()
        if ctx.app_name:
            self._add_matcher_row(AppMatcher("app_name_contains", ctx.app_name))
        elif ctx.process_name:
            self._add_matcher_row(AppMatcher("process_name_equals", ctx.process_name))

    def _save_current_profile(self, profile_id: str):
        editor = self.profile_editor_widget

        name_input = editor.findChild(QtWidgets.QLineEdit, "profile_name")
        enabled_cb = editor.findChild(QtWidgets.QCheckBox, "profile_enabled")
        preset_dropdown = editor.findChild(QtWidgets.QComboBox, "profile_preset")
        add_text = editor.findChild(QtWidgets.QPlainTextEdit, "profile_additional")

        matchers = []
        for row_widget in self._matcher_rows:
            combo = row_widget.findChild(QtWidgets.QComboBox)
            text_input = row_widget.findChild(QtWidgets.QLineEdit)
            if combo and text_input and text_input.text().strip():
                matchers.append(AppMatcher(combo.currentData(), text_input.text().strip()))

        profile = AppProfile(
            id=profile_id,
            name=name_input.text().strip() if name_input else "",
            is_enabled=enabled_cb.isChecked() if enabled_cb else True,
            matchers=matchers,
            formatting_preset=FormattingPreset(preset_dropdown.currentData()) if preset_dropdown else FormattingPreset.PLAIN_TEXT,
            additional_instructions=add_text.toPlainText() if add_text else "",
        )

        svc = AppProfileService.shared()
        svc.update_profile(profile)
        self._refresh_profile_list()

    def _add_profile(self):
        svc = AppProfileService.shared()
        p = AppProfile(name=_("New Profile"))
        svc.add_profile(p)
        self._refresh_profile_list()
        self.profile_list.setCurrentRow(len(svc.profiles) - 1)

    def _remove_profile(self):
        row = self.profile_list.currentRow()
        svc = AppProfileService.shared()
        if 0 <= row < len(svc.profiles):
            svc.delete_profile(svc.profiles[row].id)
            self._refresh_profile_list()
            UIUtils.clear_layout(self.profile_editor_layout)

    # ══════════════════════════════════════════════════════════════
    #  History Tab
    # ══════════════════════════════════════════════════════════════

    def _build_history_tab(self):
        widget = QtWidgets.QWidget()
        widget.setStyleSheet("background: transparent;")
        layout = QHBoxLayout(widget)
        layout.setContentsMargins(10, 10, 10, 10)
        layout.setSpacing(10)

        # Left panel
        left = QtWidgets.QVBoxLayout()

        self.history_search = QtWidgets.QLineEdit()
        self.history_search.setPlaceholderText(_("Search..."))
        self.history_search.setStyleSheet(self._input_style())
        self.history_search.textChanged.connect(self._filter_history)
        left.addWidget(self.history_search)

        self.history_list = QtWidgets.QListWidget()
        self.history_list.setStyleSheet(self._list_widget_style())
        self.history_list.currentRowChanged.connect(self._on_history_selected)
        left.addWidget(self.history_list)

        bottom_row = QHBoxLayout()
        self.history_count_label = QtWidgets.QLabel("")
        self.history_count_label.setStyleSheet(f"font-size: 12px; color: {'#888' if colorMode == 'dark' else '#999'};")
        bottom_row.addWidget(self.history_count_label)
        bottom_row.addStretch()
        clear_btn = QtWidgets.QPushButton(_("Clear All"))
        clear_btn.setStyleSheet(self._red_button_style())
        clear_btn.clicked.connect(self._clear_all_history)
        bottom_row.addWidget(clear_btn)
        left.addLayout(bottom_row)

        left_widget = QtWidgets.QWidget()
        left_widget.setLayout(left)
        left_widget.setFixedWidth(280)

        # Right panel — detail view
        right_scroll = QScrollArea()
        right_scroll.setWidgetResizable(True)
        right_scroll.setFrameShape(QtWidgets.QFrame.Shape.NoFrame)
        right_scroll.setStyleSheet(self._scroll_area_style())

        self.history_detail_widget = QtWidgets.QWidget()
        self.history_detail_widget.setStyleSheet("background: transparent;")
        self.history_detail_layout = QtWidgets.QVBoxLayout(self.history_detail_widget)
        self.history_detail_layout.setContentsMargins(10, 10, 10, 10)

        ph = QtWidgets.QLabel(_("Select an entry to view details"))
        ph.setStyleSheet(f"font-size: 14px; color: {'#888' if colorMode == 'dark' else '#999'};")
        ph.setAlignment(QtCore.Qt.AlignmentFlag.AlignCenter)
        self.history_detail_layout.addWidget(ph)

        right_scroll.setWidget(self.history_detail_widget)

        layout.addWidget(left_widget)
        layout.addWidget(right_scroll, 1)

        self._history_filtered_indices = []
        self._refresh_history_list()
        return widget

    def _refresh_history_list(self):
        self.history_list.clear()
        mgr = HistoryManager.shared()
        search = self.history_search.text().lower() if hasattr(self, 'history_search') else ""
        self._history_filtered_indices = []

        for i, entry in enumerate(mgr.entries):
            if search and search not in entry.command_name.lower() \
               and search not in entry.input_text.lower() \
               and search not in entry.source_app_name.lower():
                continue
            self._history_filtered_indices.append(i)
            label = f"{entry.display_timestamp}  {entry.command_name}"
            if entry.source_app_name:
                label += f"  [{entry.source_app_name}]"
            self.history_list.addItem(label)

        self.history_count_label.setText(f"{len(self._history_filtered_indices)} entries")

    def _filter_history(self):
        self._refresh_history_list()

    def _on_history_selected(self, row):
        mgr = HistoryManager.shared()
        if row < 0 or row >= len(self._history_filtered_indices):
            return
        entry = mgr.entries[self._history_filtered_indices[row]]
        self._build_history_detail(entry)

    def _build_history_detail(self, entry):
        UIUtils.clear_layout(self.history_detail_layout)
        lbl_color = f"color: {'#fff' if colorMode == 'dark' else '#333'};"

        header = QtWidgets.QLabel(f"<b>{entry.command_name}</b> \u2014 {entry.display_timestamp}")
        header.setStyleSheet(f"font-size: 16px; {lbl_color}")
        header.setWordWrap(True)
        self.history_detail_layout.addWidget(header)

        meta_parts = []
        if entry.model_name:
            meta_parts.append(f"Model: {entry.model_name}")
        if entry.source_app_name:
            meta_parts.append(f"App: {entry.source_app_name}")
        if entry.matched_profile_name:
            meta_parts.append(f"Profile: {entry.matched_profile_name}")
        if meta_parts:
            meta = QtWidgets.QLabel(" | ".join(meta_parts))
            meta.setStyleSheet(f"font-size: 12px; color: {'#aaa' if colorMode == 'dark' else '#666'};")
            meta.setWordWrap(True)
            self.history_detail_layout.addWidget(meta)

        input_label = QtWidgets.QLabel(_("Input:"))
        input_label.setStyleSheet(f"font-size: 13px; font-weight: bold; {lbl_color}")
        self.history_detail_layout.addWidget(input_label)

        input_text = QtWidgets.QPlainTextEdit(entry.input_text)
        input_text.setReadOnly(True)
        input_text.setStyleSheet(self._readonly_text_style())
        input_text.setFixedHeight(100)
        self.history_detail_layout.addWidget(input_text)

        output_label = QtWidgets.QLabel(_("Output:"))
        output_label.setStyleSheet(f"font-size: 13px; font-weight: bold; {lbl_color}")
        self.history_detail_layout.addWidget(output_label)

        output_text = QtWidgets.QPlainTextEdit(entry.output_text)
        output_text.setReadOnly(True)
        output_text.setStyleSheet(self._readonly_text_style())
        output_text.setFixedHeight(150)
        self.history_detail_layout.addWidget(output_text)

        btn_row = QHBoxLayout()
        copy_in_btn = QtWidgets.QPushButton(_("Copy Input"))
        copy_in_btn.setStyleSheet(self._green_button_style())
        copy_in_btn.clicked.connect(lambda: QtWidgets.QApplication.clipboard().setText(entry.input_text))
        btn_row.addWidget(copy_in_btn)

        copy_out_btn = QtWidgets.QPushButton(_("Copy Output"))
        copy_out_btn.setStyleSheet(self._green_button_style())
        copy_out_btn.clicked.connect(lambda: QtWidgets.QApplication.clipboard().setText(entry.output_text))
        btn_row.addWidget(copy_out_btn)

        delete_btn = QtWidgets.QPushButton(_("Delete"))
        delete_btn.setStyleSheet(self._red_button_style())
        delete_btn.clicked.connect(lambda: self._delete_history_entry(entry.id))
        btn_row.addWidget(delete_btn)

        self.history_detail_layout.addLayout(btn_row)
        self.history_detail_layout.addStretch()

    def _delete_history_entry(self, entry_id):
        HistoryManager.shared().delete(entry_id)
        self._refresh_history_list()
        UIUtils.clear_layout(self.history_detail_layout)

    def _clear_all_history(self):
        reply = QtWidgets.QMessageBox.question(
            self, _("Clear All History"),
            _("Are you sure you want to delete all history entries?"),
            QtWidgets.QMessageBox.StandardButton.Yes | QtWidgets.QMessageBox.StandardButton.No,
        )
        if reply == QtWidgets.QMessageBox.StandardButton.Yes:
            HistoryManager.shared().clear_all()
            self._refresh_history_list()
            UIUtils.clear_layout(self.history_detail_layout)

    # ══════════════════════════════════════════════════════════════
    #  Codex OAuth helpers
    # ══════════════════════════════════════════════════════════════

    def _update_codex_ui(self):
        idx = self.provider_dropdown.currentIndex()
        provider = self.app.providers[idx]
        is_codex = isinstance(provider, CodexProvider)
        self.codex_oauth_container.setVisible(is_codex)
        if is_codex:
            signed_in = provider.is_signed_in
            self.codex_sign_in_button.setVisible(not signed_in)
            self.codex_sign_out_button.setVisible(signed_in)
            self.codex_status_label.setText(_("Signed in \u2713") if signed_in else _("Not signed in"))

    def _on_codex_sign_in(self):
        idx = self.provider_dropdown.currentIndex()
        provider = self.app.providers[idx]
        if isinstance(provider, CodexProvider):
            provider.initiate_oauth()
            self.codex_status_label.setText(_("Waiting for browser..."))

    def _on_codex_sign_out(self):
        idx = self.provider_dropdown.currentIndex()
        provider = self.app.providers[idx]
        if isinstance(provider, CodexProvider):
            provider.sign_out()
            self._update_codex_ui()

    # ══════════════════════════════════════════════════════════════
    #  Style helpers
    # ══════════════════════════════════════════════════════════════

    @staticmethod
    def _input_style():
        return f"""
            font-size: 14px; padding: 5px;
            background-color: {'#444' if colorMode == 'dark' else 'white'};
            color: {'#ffffff' if colorMode == 'dark' else '#000000'};
            border: 1px solid {'#666' if colorMode == 'dark' else '#ccc'};
        """

    @staticmethod
    def _dropdown_style():
        return f"""
            font-size: 14px; padding: 5px;
            background-color: {'#444' if colorMode == 'dark' else 'white'};
            color: {'#ffffff' if colorMode == 'dark' else '#000000'};
            border: 1px solid {'#666' if colorMode == 'dark' else '#ccc'};
        """

    @staticmethod
    def _list_widget_style():
        return f"""
            QListWidget {{
                font-size: 13px;
                background-color: {'#333' if colorMode == 'dark' else '#f9f9f9'};
                color: {'#fff' if colorMode == 'dark' else '#333'};
                border: 1px solid {'#555' if colorMode == 'dark' else '#ccc'};
            }}
            QListWidget::item:selected {{
                background-color: {'#555' if colorMode == 'dark' else '#cde'};
            }}
        """

    @staticmethod
    def _readonly_text_style():
        return f"""
            font-size: 13px; padding: 5px;
            background-color: {'#2a2a2a' if colorMode == 'dark' else '#f5f5f5'};
            color: {'#ddd' if colorMode == 'dark' else '#333'};
            border: 1px solid {'#555' if colorMode == 'dark' else '#ccc'};
        """

    @staticmethod
    def _green_button_style():
        return f"""
            QPushButton {{
                background-color: {'#4CAF50' if colorMode == 'dark' else '#008CBA'};
                color: white; padding: 8px 12px; font-size: 14px;
                border: none; border-radius: 5px;
            }}
            QPushButton:hover {{
                background-color: {'#45a049' if colorMode == 'dark' else '#007095'};
            }}
        """

    @staticmethod
    def _red_button_style():
        return f"""
            QPushButton {{
                background-color: #c0392b;
                color: white; padding: 8px 12px; font-size: 14px;
                border: none; border-radius: 5px;
            }}
            QPushButton:hover {{
                background-color: #a93226;
            }}
        """

    @staticmethod
    def _scroll_area_style():
        return """
            QScrollArea {
                background: transparent;
                border: none;
            }
            QScrollArea > QWidget > QWidget {
                background: transparent;
            }
            QScrollBar:vertical {
                background-color: transparent;
                width: 12px; margin: 0px;
            }
            QScrollBar::handle:vertical {
                background-color: rgba(128, 128, 128, 0.5);
                min-height: 20px; border-radius: 6px; margin: 2px;
            }
            QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {
                height: 0px;
            }
        """

    @staticmethod
    def toggle_autostart(state):
        """Toggle the autostart setting."""
        AutostartManager.set_autostart(state == 2)

    def save_settings(self):
        """Save the current settings."""
        self.app.config['locale'] = 'en'

        if not self.providers_only:
            self.app.config['shortcut'] = self.shortcut_input.text()
            self.app.config['theme'] = 'gradient' if self.gradient_radio.isChecked() else 'plain'
            if hasattr(self, 'history_checkbox') and self.history_checkbox:
                self.app.config['is_history_enabled'] = self.history_checkbox.isChecked()
        else:
            self.app.create_tray_icon()

        self.app.config['streaming'] = False
        self.app.config['provider'] = self.provider_dropdown.currentText()

        self.app.providers[self.provider_dropdown.currentIndex()].save_config()

        provider_name = self.app.config.get('provider', 'Gemini')
        self.app.current_provider = next(
            (provider for provider in self.app.providers if provider.provider_name == provider_name),
            self.app.providers[0]
        )

        self.app.current_provider.load_config(
            self.app.config.get("providers", {}).get(provider_name, {})
        )

        self.app.register_hotkey()
        self.providers_only = False
        self.close()

    def closeEvent(self, event):
        """Handle window close event."""
        if self.providers_only:
            self.close_signal.emit()
        super().closeEvent(event)