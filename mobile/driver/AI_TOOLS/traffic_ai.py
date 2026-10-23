import sys
from ollama import chat

from PySide6.QtCore import Qt, QThread, Signal, QTimer
from PySide6.QtGui import QColor, QFont
from PySide6.QtWidgets import (
    QApplication,
    QFrame,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMainWindow,
    QPushButton,
    QVBoxLayout,
    QWidget,
    QScrollArea,
)


# =========================
# Traffic Light Functions
# =========================

def pedestrian_crossing():
    print("\n🚦 الإشارة: 🔴 أحمر للعربيات")
    print("🚶 المشاة: يمكنهم العبور\n")
    return "تم تفعيل إشارة عبور المشاة: الأحمر للعربيات والمشاة يمكنهم العبور."


def vehicle_crossing():
    print("\n🚦 الإشارة: 🟢 أخضر للعربيات")
    print("🚗 العربيات: يمكنها العبور\n")
    return "تم تفعيل إشارة عبور العربيات: الأخضر للعربيات."


def traffic_status():
    print("\n🚦 حالة الإشارة الحالية")
    print("🔴 أحمر للعربيات")
    print("🚶 المشاة يمكنهم العبور\n")
    return "حالة الإشارة الحالية: أحمر للعربيات والمشاة يمكنهم العبور."


# =========================
# Tools available to the AI
# =========================

tools = [
    {
        "type": "function",
        "function": {
            "name": "pedestrian_crossing",
            "description": "تشغيل إشارة عبور المشاة عندما يكون المستخدم شخصًا ماشيًا على قدميه ويريد عبور الشارع.",
            "parameters": {"type": "object", "properties": {}},
        },
    },
    {
        "type": "function",
        "function": {
            "name": "vehicle_crossing",
            "description": "تشغيل إشارة عبور السيارات عندما يكون المستخدم يقود سيارة ويريد عبور الشارع.",
            "parameters": {"type": "object", "properties": {}},
        },
    },
    {
        "type": "function",
        "function": {
            "name": "traffic_status",
            "description": "معرفة حالة إشارة المرور الحالية.",
            "parameters": {"type": "object", "properties": {}},
        },
    },
]


# =========================
# System instructions
# =========================

messages = [
    {
        "role": "system",
        "content": """
أنت نظام ذكي للتحكم في إشارة مرور.
تحدث مع المستخدم باللغة العربية.
افهم طلب المستخدم من كلامه الطبيعي ولا تطلب منه اسم أي function.
إذا كان المستخدم مشاة ويريد عبور الشارع استخدم pedestrian_crossing.
إذا كان المستخدم يقود سيارة ويريد عبور الشارع استخدم vehicle_crossing.
إذا كان المستخدم يسأل عن حالة إشارة المرور الحالية استخدم traffic_status.
إذا كانت المعلومات غير كافية أو غامضة، لا تخمن. اسأل المستخدم سؤالًا توضيحيًا.
استخدم الـfunctions عندما يكون تنفيذها مناسبًا.
""",
    }
]


# =========================
# Background Worker Thread (Fixes Not Responding)
# =========================

class OllamaWorker(QThread):
    finished = Signal(str, str)  # (answer, new_state)
    error = Signal(str)

    def __init__(self, user_input, current_state):
        super().__init__()
        self.user_input = user_input
        self.current_state = current_state

    def run(self):
        try:
            messages.append({
                "role": "user",
                "content": self.user_input
            })

            response = chat(
                model="qwen3:8b",
                messages=messages,
                tools=tools
            )

            messages.append(response.message)

            new_state = None
            result = ""

            if response.message.tool_calls:
                for tool_call in response.message.tool_calls:
                    function_name = tool_call.function.name

                    if function_name == "pedestrian_crossing":
                        new_state = "red"
                        result = pedestrian_crossing()
                    elif function_name == "vehicle_crossing":
                        new_state = "green"
                        result = vehicle_crossing()
                    elif function_name == "traffic_status":
                        result = traffic_status()
                        if self.current_state not in ["red", "green"]:
                            new_state = "red"
                    else:
                        result = "Function غير معروفة."
                        new_state = "yellow"

                    messages.append({
                        "role": "tool",
                        "content": result
                    })

                final_response = chat(
                    model="qwen3:8b",
                    messages=messages,
                    tools=tools
                )

                messages.append(final_response.message)
                answer = final_response.message.content
                if not new_state:
                    new_state = "red" if result else "yellow"
            else:
                new_state = "yellow"
                answer = response.message.content

            if not answer:
                answer = "تم تنفيذ الطلب."

            self.finished.emit(answer, new_state)

        except Exception as e:
            self.error.emit(str(e))


# =========================
# Main UI
# =========================

class TrafficApp(QMainWindow):

    def __init__(self):
        super().__init__()

        self.setWindowTitle("Smart Traffic AI")
        self.resize(1050, 700)

        self.current_state = "yellow"
        self.thinking_widget = None
        self.dot_count = 1

        # انيميشن نقاط التفكير
        self.thinking_timer = QTimer(self)
        self.thinking_timer.setInterval(400)
        self.thinking_timer.timeout.connect(self.update_thinking_animation)

        self.setup_ui()
        self.update_traffic_light("yellow")

    def setup_ui(self):
        central = QWidget()
        self.setCentralWidget(central)

        main_layout = QHBoxLayout(central)
        main_layout.setContentsMargins(25, 25, 25, 25)
        main_layout.setSpacing(25)

        # =========================
        # Left - Traffic Light Panel
        # =========================
        traffic_panel = QFrame()
        traffic_panel.setObjectName("trafficPanel")

        traffic_layout = QVBoxLayout(traffic_panel)
        traffic_layout.setAlignment(Qt.AlignCenter)

        title = QLabel("SMART TRAFFIC")
        title.setAlignment(Qt.AlignCenter)
        title.setFont(QFont("Arial", 20, QFont.Bold))

        subtitle = QLabel("AI Traffic Control")
        subtitle.setAlignment(Qt.AlignCenter)
        subtitle.setObjectName("subtitle")

        traffic_body = QFrame()
        traffic_body.setObjectName("trafficBody")

        light_layout = QVBoxLayout(traffic_body)
        light_layout.setContentsMargins(25, 30, 25, 30)
        light_layout.setSpacing(18)

        self.red_light = QLabel()
        self.yellow_light = QLabel()
        self.green_light = QLabel()

        for light in [self.red_light, self.yellow_light, self.green_light]:
            light.setFixedSize(100, 100)
            light.setAlignment(Qt.AlignCenter)

        light_layout.addWidget(self.red_light)
        light_layout.addWidget(self.yellow_light)
        light_layout.addWidget(self.green_light)

        self.state_label = QLabel("🟡 الإشارة صفراء - بانتظار توضيح الطلب")
        self.state_label.setAlignment(Qt.AlignCenter)
        self.state_label.setWordWrap(True)
        self.state_label.setFont(QFont("Arial", 14, QFont.Bold))

        traffic_layout.addWidget(title)
        traffic_layout.addWidget(subtitle)
        traffic_layout.addSpacing(25)
        traffic_layout.addWidget(traffic_body)
        traffic_layout.addSpacing(20)
        traffic_layout.addWidget(self.state_label)

        # =========================
        # Right - Chat Panel (with ScrollArea)
        # =========================
        chat_panel = QFrame()
        chat_panel.setObjectName("chatPanel")

        chat_layout = QVBoxLayout(chat_panel)
        chat_layout.setContentsMargins(20, 20, 20, 20)

        chat_title = QLabel("مساعد المرور الذكي")
        chat_title.setFont(QFont("Arial", 20, QFont.Bold))

        chat_subtitle = QLabel("اتكلم مع النظام بشكل طبيعي")
        chat_subtitle.setObjectName("subtitle")

        # Scroll Area Setup
        self.scroll_area = QScrollArea()
        self.scroll_area.setWidgetResizable(True)
        self.scroll_area.setFrameShape(QScrollArea.NoFrame)
        self.scroll_area.setObjectName("scrollArea")

        self.chat_container = QWidget()
        self.chat_container.setObjectName("chatAreaContainer")
        self.chat_layout = QVBoxLayout(self.chat_container)
        self.chat_layout.setAlignment(Qt.AlignTop)
        self.chat_layout.setSpacing(12)

        self.scroll_area.setWidget(self.chat_container)

        # Welcome message
        self.add_message(
            "AI",
            "أهلاً! أنا نظام التحكم الذكي في إشارة المرور.\n"
            "قولي مثلاً: أنا ماشي وعاوز أعدي الشارع، أو أنا سايق عربية."
        )

        # Input & Send Layout
        input_layout = QHBoxLayout()
        input_layout.setSpacing(10)

        self.input_box = QLineEdit()
        self.input_box.setPlaceholderText("اكتب طلبك هنا...")
        self.input_box.setMinimumHeight(50)

        self.send_button = QPushButton("إرسال")
        self.send_button.setMinimumSize(100, 50)

        self.send_button.clicked.connect(self.send_message)
        self.input_box.returnPressed.connect(self.send_message)

        input_layout.addWidget(self.input_box)
        input_layout.addWidget(self.send_button)

        chat_layout.addWidget(chat_title)
        chat_layout.addWidget(chat_subtitle)
        chat_layout.addSpacing(15)
        chat_layout.addWidget(self.scroll_area, 1)
        chat_layout.addSpacing(12)
        chat_layout.addLayout(input_layout)

        main_layout.addWidget(traffic_panel, 1)
        main_layout.addWidget(chat_panel, 2)

        # =========================
        # Stylesheet
        # =========================
        self.setStyleSheet("""
            QMainWindow {
                background: #101216;
            }
            QFrame#trafficPanel, QFrame#chatPanel {
                background: #181b21;
                border: 1px solid #292d35;
                border-radius: 18px;
            }
            QLabel {
                color: #ffffff;
            }
            QLabel#subtitle {
                color: #8d95a3;
                font-size: 13px;
            }
            QFrame#trafficBody {
                background: #0b0d10;
                border-radius: 50px;
                border: 2px solid #292d35;
            }
            QScrollArea#scrollArea {
                background: #0f1115;
                border-radius: 14px;
                border: 1px solid #242831;
            }
            QWidget#chatAreaContainer {
                background: #0f1115;
            }
            QLineEdit {
                background: #0e1014;
                border: 1px solid #303641;
                border-radius: 12px;
                padding: 0 15px;
                color: white;
                font-size: 15px;
            }
            QLineEdit:focus {
                border: 1px solid #596273;
            }
            QPushButton {
                background: #2d6cdf;
                color: white;
                border: none;
                border-radius: 12px;
                font-size: 15px;
                font-weight: bold;
            }
            QPushButton:hover {
                background: #3b7af0;
            }
            QPushButton:pressed {
                background: #245bbd;
            }
            QPushButton:disabled {
                background: #3a414e;
                color: #8d95a3;
            }
            QScrollBar:vertical {
                background: #0f1115;
                width: 8px;
                margin: 0px;
                border-radius: 4px;
            }
            QScrollBar::handle:vertical {
                background: #303641;
                min-height: 20px;
                border-radius: 4px;
            }
            QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {
                height: 0px;
            }
        """)

    # =========================
    # Traffic Light Logic
    # =========================

    def set_light_style(self, light, color, active=False):
        if active:
            light.setStyleSheet(f"""
                QLabel {{
                    background: {color};
                    border-radius: 50px;
                    border: 5px solid #ffffff;
                }}
            """)
        else:
            light.setStyleSheet("""
                QLabel {
                    background: #24272d;
                    border-radius: 50px;
                    border: 5px solid #15171b;
                }
            """)

    def update_traffic_light(self, state):
        self.current_state = state

        self.set_light_style(self.red_light, "#ff3030", state == "red")
        self.set_light_style(self.yellow_light, "#ffd21f", state == "yellow")
        self.set_light_style(self.green_light, "#27d85b", state == "green")

        if state == "red":
            self.state_label.setText("🔴 أحمر للعربيات\n🚶 المشاة يمكنهم العبور")
        elif state == "green":
            self.state_label.setText("🟢 أخضر للعربيات\n🚗 العربيات يمكنها العبور")
        else:
            self.state_label.setText("🟡 الإشارة صفراء\n❓ يرجى توضيح ما إذا كنت مشاة أم سائق سيارة")

    # =========================
    # Chat UI Helpers
    # =========================

    def add_message(self, sender, text):
        container = QFrame()
        if sender == "AI":
            container.setStyleSheet("""
                QFrame {
                    background: #1b2028;
                    border-radius: 12px;
                    padding: 8px;
                }
            """)
        else:
            container.setStyleSheet("""
                QFrame {
                    background: #245bbd;
                    border-radius: 12px;
                    padding: 8px;
                }
            """)

        layout = QVBoxLayout(container)
        layout.setContentsMargins(12, 10, 12, 10)

        sender_label = QLabel(sender)
        sender_label.setFont(QFont("Arial", 10, QFont.Bold))

        message_label = QLabel(text)
        message_label.setWordWrap(True)
        message_label.setTextInteractionFlags(Qt.TextSelectableByMouse)

        layout.addWidget(sender_label)
        layout.addWidget(message_label)

        self.chat_layout.addWidget(container)
        self.scroll_to_bottom()

    def add_thinking_message(self):
        container = QFrame()
        container.setStyleSheet("""
            QFrame {
                background: #1b2028;
                border-radius: 12px;
                padding: 8px;
            }
        """)
        layout = QVBoxLayout(container)
        layout.setContentsMargins(12, 10, 12, 10)

        sender_label = QLabel("AI")
        sender_label.setFont(QFont("Arial", 10, QFont.Bold))

        self.thinking_label = QLabel("🤖 جاري التفكير ومعالجة الطلب.")
        self.thinking_label.setObjectName("subtitle")

        layout.addWidget(sender_label)
        layout.addWidget(self.thinking_label)

        self.chat_layout.addWidget(container)
        self.scroll_to_bottom()
        return container

    def update_thinking_animation(self):
        if self.thinking_widget and hasattr(self, 'thinking_label'):
            dots = "." * self.dot_count
            self.thinking_label.setText(f"🤖 جاري التفكير ومعالجة الطلب{dots}")
            self.dot_count = (self.dot_count % 3) + 1

    def remove_thinking_message(self):
        if self.thinking_widget:
            self.thinking_timer.stop()
            self.chat_layout.removeWidget(self.thinking_widget)
            self.thinking_widget.deleteLater()
            self.thinking_widget = None

    def scroll_to_bottom(self):
        QTimer.singleShot(50, lambda: self.scroll_area.verticalScrollBar().setValue(
            self.scroll_area.verticalScrollBar().maximum()
        ))

    # =========================
    # Send Message Trigger
    # =========================

    def send_message(self):
        user_input = self.input_box.text().strip()
        if not user_input:
            return

        self.input_box.clear()
        self.send_button.setEnabled(False)

        # 1. إظهار رسالة المستخدم فوراً في الشات
        self.add_message("أنت", user_input)

        # 2. إظهار انيميشن التفكير المتحرك
        self.thinking_widget = self.add_thinking_message()
        self.dot_count = 1
        self.thinking_timer.start()

        # 3. تشغيل الموديل في Thread منفصل لعدم تجميد البرنامج
        self.worker = OllamaWorker(user_input, self.current_state)
        self.worker.finished.connect(self.on_worker_finished)
        self.worker.error.connect(self.on_worker_error)
        self.worker.start()

    def on_worker_finished(self, answer, new_state):
        self.remove_thinking_message()
        self.update_traffic_light(new_state)
        self.add_message("AI", answer)

        self.send_button.setEnabled(True)
        self.input_box.setFocus()

    def on_worker_error(self, err_msg):
        self.remove_thinking_message()
        self.update_traffic_light("yellow")
        self.add_message("AI", f"حدث خطأ أثناء الاتصال بالموديل:\n{err_msg}")

        self.send_button.setEnabled(True)
        self.input_box.setFocus()


# =========================
# Run Application
# =========================

if __name__ == "__main__":
    app = QApplication(sys.argv)
    app.setStyle("Fusion")

    window = TrafficApp()
    window.show()

    sys.exit(app.exec())