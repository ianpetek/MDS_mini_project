classdef ModeMotors < Simulink.IntEnumType
    enumeration
        Off(0)
        GoTo(1)
        % ... one entry per FSM state
    end
end