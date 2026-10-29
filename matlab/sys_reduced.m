function dx = sys_reduced(x, u, p)
%SYS_REDUCED  Reduced CoreXY printer dynamics, dx = f(x, u).
%   Electrical states are replaced by their quasi-static values
%   (L_m -> 0 for the motors, u_c = u_n for the nozzle circuit), since they
%   settle in micro- to milliseconds, far faster than mechanics and thermals.
%   x = [x; y; xdot; ydot; T_n; T_r]   (auxiliary states to be appended)
%   u = [u_mL; u_mR; u_n]

dx = zeros(size(x));   % fixed size, required for MATLAB Function blocks
ix = p.red.idx;

xdot = x(ix.xdot);  ydot = x(ix.ydot);
T_n  = x(ix.T_n);   T_r  = x(ix.T_r);
u_mL = u(1);  u_mR = u(2);  u_n = u(3);

% Motors: algebraic currents from L_m*di/dt = 0
i_L = (u_mL - p.K_m*(xdot + ydot)/p.r_m)/p.R_m;
i_R = (u_mR - p.K_m*(xdot - ydot)/p.r_m)/p.R_m;

% Mechanics (same equations as the full model)
dx(ix.x)    = xdot;
dx(ix.y)    = ydot;
dx(ix.xdot) = -p.b_x/p.m_eq*xdot + p.kf*(i_L + i_R);
dx(ix.ydot) = -p.b_y/p.m_eq*ydot + p.kf*(i_L - i_R);

% Nozzle: u_c = u_n, so the heater sees the input voltage directly
R_n = p.R0*(1 + p.alpha*(T_r - p.T0));
P_r = u_n^2/R_n;
dx(ix.T_n) = ((T_r - T_n)/p.Rt_n - (T_n - p.T_e)/p.R_env)/p.C_tn;
dx(ix.T_r) = (P_r - (T_r - T_n)/p.Rt_n)/p.C_r;

% Auxiliary states (e.g. filament used / wiped): add here
end