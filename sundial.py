import time
import math
import matplotlib.pyplot as plt

class Sundial:
    def __init__(self, latitude):
        self.latitude = latitude
        self.time_zone_offset = 0  # UTC

    def set_time_zone(self, offset):
        self.time_zone_offset = offset

    def calculate_sundial_position(self):
        # Get current time
        utc_time = time.gmtime()
        local_time = time.localtime()
        hour = (utc_time.tm_hour + self.time_zone_offset) % 24
        minute = utc_time.tm_min

        # Calculate the sun's position
        hour_angle = (hour + minute / 60.0) * 15.0  # Degrees

        # Calculate the shadow length and height
        shadow_length = math.tan(math.radians(90 - self.latitude)) / math.tan(math.radians(hour_angle))

        return hour_angle, shadow_length

    def plot_sundial(self):
        hour_angle, shadow_length = self.calculate_sundial_position()
        plt.figure(figsize=(8, 6))
        plt.subplot(1, 1, 1)
        plt.plot([0, hour_angle], [0, shadow_length], label='Shadow')
        plt.xlim(0, 360)
        plt.ylim(0, 5)
        plt.title('Sundial Position')
        plt.xlabel('Hour Angle (degrees)')
        plt.ylabel('Shadow Length')
        plt.grid()
        plt.legend()
        plt.show()

# Example usage
sundial = Sundial(latitude=52.52)  # Berlin
sundial.set_time_zone(1)  # CET
sundial.plot_sundial()