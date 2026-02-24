import kivy
from kivy.app import App
from kivy.uix.boxlayout import BoxLayout
from kivy.garden.mapview import MapView

class SundialApp(App):
    def build(self):
        layout = BoxLayout(orientation='vertical')
        map_view = MapView()
        layout.add_widget(map_view)
        return layout

if __name__ == '__main__':
    SundialApp().run()