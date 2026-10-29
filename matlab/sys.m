function dx = sys(x, u, p)
%SYS  Continuous dynamics of the CoreXY printer, dx = f(x, u).
%   x = [x; y; xdot; ydot; i_L; i_R]   (nozzle + auxiliary states to be appended)
%   u = [u_mL; u_mR]                    (nozzle voltage to be appended)
%   Pure physics only: no mode logic here. The supervisor acts through u,
%   and resets are applied outside (Integrator reset port / solver restart).

dx = zeros(p.nx, 1);   % fixed size, required for MATLAB Function blocks

% Mechanical block: coupled CoreXY kinematics + DC motors (linear)
im = p.idx.mech;
dx(im) = p.A*x(im) + p.B*u(1:2);

% nozzle part
i_Ln = x(p.idx.i_Ln);  u_c = x(p.idx.u_c);
T_n  = x(p.idx.T_n);   T_r = x(p.idx.T_r);
u_n  = u(3);

R_n = p.R0*(1 + p.alpha*(T_r - p.T0));   % (1.29)
P_r = u_c^2/R_n;                          % heating power

dx(p.idx.i_Ln) = (u_n - u_c)/p.L_n;                                   % (1.27)
dx(p.idx.u_c)  = (i_Ln - u_c/R_n)/p.C_n;
dx(p.idx.T_n)  = ((T_r - T_n)/p.Rt_n - (T_n - p.T_e)/p.R_env)/p.C_tn; % (1.28)
dx(p.idx.T_r)  = (P_r - (T_r - T_n)/p.Rt_n)/p.C_r;

% Auxiliary states (e.g. filament used / wiped): add here

end