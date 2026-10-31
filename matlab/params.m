%% Parameters from the task
p.m     = 60e-3;     % tool head mass                      [kg]
p.r_m   = 11e-3;     % motor radius                        [m]
p.r_b   = 3e-3;      % bearing radius                      [m]
p.J_m   = 8e-6;      % motor inertia                       [kg m^2]
p.L_m   = 10e-3;     % motor inductance                    [H]
p.R_m   = 90;        % motor resistance                    [Ohm]
p.K_m   = 0.07;      % motor constant                      [N m/A]
p.mu_r  = 2.7e-8;    % bearing friction, rotational        [N m s/rad]
p.mu_lx = 0.002;     % bearing friction, linear x          [N s/m]
p.mu_ly = 0.001;     % bearing friction, linear y          [N s/m]

% thermal nozzle part
p.L_n   = 1e-3;      % nozzle inductance                  [H]
p.C_n   = 1e-6;      % nozzle capacitance                 [F]
p.R0    = 8;         % heater resistance at T0            [Ohm]
p.alpha = 4e-4;      % temperature coefficient            [1/K]
p.T0    = 293.15;    % reference temperature              [K]
p.C_tn  = 2;        % nozzle thermal capacity            [J/K]
p.C_r   = 0.5;         % resistor thermal capacity          [J/K]
p.Rt_n  = 9;         % resistor -> nozzle thermal res.    [K/W]
p.R_env = 15;        % nozzle -> environment/filament     [K/W]
p.T_e   = 300;       % environment temperature            [K]
p.T_n_ref = 240 + 273.15;   % target nozzle temperature   [K]

%% Derived quantities
p.m_eq = p.m + 2*p.J_m/p.r_m^2;            % equivalent mass   [kg]
p.b_x  = 8*p.mu_r/p.r_b^2 + 2*p.mu_lx;     % damping x         [N s/m]
p.b_y  = 4*p.mu_r/p.r_b^2 + 2*p.mu_ly;     % damping y         [N s/m]
p.kf   = p.K_m/(p.m_eq*p.r_m);
p.ke   = p.K_m/(p.r_m*p.L_m);

%% State and input layout (shared with events / supervisor)
% x = [x; y; xdot; ydot; i_L; i_R, i_Ln, u_c, T_n, T_r],  u = [u_mL; u_mR, u_n]
p.idx.x    = 1;  p.idx.y    = 2;
p.idx.xdot = 3;  p.idx.ydot = 4;
p.idx.i_L  = 5;  p.idx.i_R  = 6;
p.idx.mech = 1:6;          % mechanical block
% nozzle part x_n = [i_Ln, u_c, T_n, T_r]
p.idx.i_Ln = 7;  p.idx.u_c = 8;
p.idx.T_n  = 9;  p.idx.T_r = 10;
p.idx.noz  = 7:10;         % nozzle block

p.nx = 10;                  % total number of states
p.nu = 3;                  % total number of inputs
p.x0 = zeros(p.nx, 1);     % initial state
p.x0([p.idx.T_n, p.idx.T_r]) = p.T_e; 

% reduced model for simulation purpuses
red_names = {'x','y','xdot','ydot','T_n','T_r'};
for k = 1:numel(red_names)
    p.red.idx.(red_names{k}) = k;
end
p.red.nx = numel(red_names);
p.red.x0 = zeros(p.red.nx, 1);
p.red.x0([p.red.idx.T_n, p.red.idx.T_r]) = p.T_e;

%% Coupled model
kf = p.kf;  ke = p.ke;  R_m = p.R_m;  L_m = p.L_m;  m_eq = p.m_eq;
p.A = [0 0  1            0            0         0;
    0 0  0            1            0         0;
    0 0 -p.b_x/m_eq   0            kf        kf;
    0 0  0           -p.b_y/m_eq   kf       -kf;
    0 0 -ke          -ke          -R_m/L_m   0;
    0 0 -ke           ke           0        -R_m/L_m];
p.B = [0      0;
    0      0;
    0      0;
    0      0;
    1/L_m  0;
    0      1/L_m];

%% Decoupled model: x_dec = [x; xdot; i_x; y; ydot; i_y], u_dec = [u_mx; u_my]
Ax = [0  1            0;
    0 -p.b_x/m_eq   kf;
    0 -2*ke        -R_m/L_m];
Ay = [0  1            0;
    0 -p.b_y/m_eq   kf;
    0 -2*ke        -R_m/L_m];
Bi = [0; 0; 1/L_m];
p.Adec = blkdiag(Ax, Ay);
p.Bdec = blkdiag(Bi, Bi);

%% Coupled -> decoupled transformation
% i_x = i_L + i_R,  i_y = i_L - i_R,  u_mx = u_mL + u_mR,  u_my = u_mL - u_mR
p.Tx = [1 0 0 0 0 0;    % x
    0 0 1 0 0 0;    % xdot
    0 0 0 0 1 1;    % i_x
    0 1 0 0 0 0;    % y
    0 0 0 1 0 0;    % ydot
    0 0 0 0 1 -1];  % i_y
p.Tu = [1  1;
    1 -1];


%% LTI objects for analysis (kept outside p: ss objects don't work in
%  MATLAB Function blocks). Named G_* so they don't shadow sys.m.
C = [1 0 0 0 0 0;
    0 1 0 0 0 0];
G_c = ss(p.A, p.B, C, zeros(2,2));
G_c.StateName  = {'x','y','xdot','ydot','i_L','i_R'};
G_c.InputName  = {'u_mL','u_mR'};
G_c.OutputName = {'x','y'};

Ct = [1 0 0 0 0 0;
    0 0 0 1 0 0];
G_dec = ss(p.Adec, p.Bdec, Ct, zeros(2,2));
G_dec.StateName  = {'x','xdot','i_x','y','ydot','i_y'};
G_dec.InputName  = {'u_mx','u_my'};
G_dec.OutputName = {'x','y'};

clear kf ke R_m L_m m_eq Ax Ay Bi C Ct

%% Bus mapping (only measurable values)
% state_names = {'x','y','xdot','ydot','i_L','i_R','i_Ln','u_c','T_n','T_r'};
state_names = {'x','y','xdot','ydot','T_n'};
indices = [1,2,3,4,5];

elems = Simulink.BusElement.empty;
for k = 1:numel(state_names)
    elems(k) = Simulink.BusElement;
    elems(k).Name = state_names{k};
    p.idx.(state_names{k}) = indices(k);     
end
PlantState = Simulink.Bus;
PlantState.Elements = elems;


%% Filament change (Q2.1 / Q3.1)
p.wipe_x      = 0;     % wipe-tower location [m]
p.wipe_y      = 0;
p.tol         = 0.005; % "arrived" tolerance [m]
p.t_timeout   = 30;    % a step counts as failed after this [s]
p.t_wipe      = 3;     % time spent wiping [s]
p.t_load      = 2;     % time to load new filament [s]
p.max_retries = 3;
%% Print path: one row per point, columns [x y] in metres
th = linspace(0, 2*pi, 41)';            % example: circle, 40 segments
p.path = [0.0 0.0;
    0.05 0.0;
    0.05 0.05;
    0.0 0.05;
    0.0 0.0];
p.n_path   = size(p.path, 1);           
p.tol_pass = 0.003;                     % "close enough, next point" [m]

PAUSE_pressed = [0 0];

%% Filament change inputs: [time value]
C_pressed = [0 0];   % press C at 15 s (mid-print)
F_pressed = [0 0];               % never

%% Filament change settings
p.wipe_x = 0;  p.wipe_y = 0.5;   % wipe location [m]
p.t_wipe = 3;                  % wiping time [s]
p.t_load = 5;                  % loading time [s]
p.fil_max = 13;
p.L_bed = 0.5;  