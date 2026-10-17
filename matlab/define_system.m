%% define_system.m
% CoreXY 3D printer: parameters and state-space models of coupled and
% decoupled system

%% Parameters from the task
m     = 60e-3;     % tool head mass                      [kg]
r_m   = 11e-3;     % motor radius                        [m]
r_b   = 3e-3;      % bearing radius                      [m]
J_m   = 8e-6;      % motor inertia                       [kg m^2]
L_m   = 10e-3;     % motor inductance                    [H]
R_m   = 90;        % motor resistance                    [Ohm]
K_m   = 0.07;      % motor constant                      [N m/A]
mu_r  = 2.7e-8;    % bearing friction, rotational        [N m s/rad]
mu_lx = 0.002;     % bearing friction, linear x          [N s/m]
mu_ly = 0.001;     % bearing friction, linear y          [N s/m]


m_eq = m + 2*J_m/r_m^2;
b_x  = 8*mu_r/r_b^2 + 2*mu_lx;
b_y  = 8*mu_r/r_b^2 + 2*mu_ly;

%% Coupled model: x = [x; y; xdot; ydot; i_L; i_R], u = [u_mL; u_mR]
kf = K_m/(m_eq*r_m);
ke = K_m/(r_m*L_m);

A = [0 0  1          0          0         0;
    0 0  0          1          0         0;
    0 0 -b_x/m_eq   0          kf        kf;
    0 0  0         -b_y/m_eq   kf       -kf;
    0 0 -ke        -ke        -R_m/L_m   0;
    0 0 -ke         ke         0        -R_m/L_m];

B = [0      0;
    0      0;
    0      0;
    0      0;
    1/L_m  0;
    0      1/L_m];

C = [1 0 0 0 0 0;
    0 1 0 0 0 0];
D = zeros(2,2);

sys = ss(A, B, C, D);
sys.StateName  = {'x','y','xdot','ydot','i_L','i_R'};
sys.InputName  = {'u_mL','u_mR'};
sys.OutputName = {'x','y'};

%% Decoupled model:
Ax = [0  1          0;
    0 -b_x/m_eq   kf;
    0 -2*ke      -R_m/L_m];
Ay = [0  1          0;
    0 -b_y/m_eq   kf;
    0 -2*ke      -R_m/L_m];
Bi = [0; 0; 1/L_m];

At = blkdiag(Ax, Ay);
Bt = blkdiag(Bi, Bi);
Ct = [1 0 0 0 0 0;
    0 0 0 1 0 0];
Dt = zeros(2,2);

sys_dec = ss(At, Bt, Ct, Dt);
sys_dec.StateName  = {'x','xdot','i_x','y','ydot','i_y'};
sys_dec.InputName  = {'u_mx','u_my'};
sys_dec.OutputName = {'x','y'};