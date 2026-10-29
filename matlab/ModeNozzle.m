classdef ModeNozzle < Simulink.IntEnumType
    enumeration
        Off(0)
        HeatNozzle(1)
        % ... one entry per FSM state
    end
end