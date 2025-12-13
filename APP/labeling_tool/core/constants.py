from enum import IntEnum

class LabelType(IntEnum):
    SMASH = 1
    DRIVE = 2
    TOSS = 3
    DROP = 4
    OTHER = 5
    
    @staticmethod
    def to_str(value):
        if value == LabelType.SMASH: return "Smash"
        if value == LabelType.DRIVE: return "Drive"
        if value == LabelType.TOSS: return "Toss"
        if value == LabelType.DROP: return "Drop"
        if value == LabelType.OTHER: return "Other"
        return "Unknown"
        
    @staticmethod
    def get_color(value):
        if value == LabelType.SMASH: return "red"
        if value == LabelType.DRIVE: return "orange"
        if value == LabelType.TOSS: return "yellow"
        if value == LabelType.DROP: return "blue"
        if value == LabelType.OTHER: return "gray"
        return "black"
