%% Local functions
function [sys_p, sys_dec_p] = perturbed_system(p)

%pert = @(v) v .* (1 + (p/100) * (2*rand - 1));
pert = @(v) v .* (1 + (p/100) * sign((2*rand - 1)));


m     = pert(60e-3);
r_m   = pert(11e-3);
r_b   = pert(3e-3);
J_m   = pert(8e-6);
L_m   = pert(10e-3);
R_m   = pert(90);
K_m   = pert(0.07);
mu_r  = pert(2.7e-8);
mu_lx = pert(0.002);
mu_ly = pert(0.001);

fprintf('\nRelative Changes (%%):\n');
fprintf('m:     %+.2f%%\n', (m / 60e-3 - 1) * 100);
fprintf('r_m:   %+.2f%%\n', (r_m / 11e-3 - 1) * 100);
fprintf('r_b:   %+.2f%%\n', (r_b / 3e-3 - 1) * 100);
fprintf('J_m:   %+.2f%%\n', (J_m / 8e-6 - 1) * 100);
fprintf('L_m:   %+.2f%%\n', (L_m / 10e-3 - 1) * 100);
fprintf('R_m:   %+.2f%%\n', (R_m / 90 - 1) * 100);
fprintf('K_m:   %+.2f%%\n', (K_m / 0.07 - 1) * 100);
fprintf('mu_r:  %+.2f%%\n', (mu_r / 2.7e-8 - 1) * 100);
fprintf('mu_lx: %+.2f%%\n', (mu_lx / 0.002 - 1) * 100);
fprintf('mu_ly: %+.2f%%\n', (mu_ly / 0.001 - 1) * 100);

m_eq = m + 2*J_m/r_m^2;
b_x  = 8*mu_r/r_b^2 + 2*mu_lx;
b_y  = 8*mu_r/r_b^2 + 2*mu_ly;
kf   = K_m/(m_eq*r_m);
ke   = K_m/(r_m*L_m);

% Coupled
A = [0 0  1          0          0         0;
    0 0  0          1          0         0;
    0 0 -b_x/m_eq   0          kf        kf;
    0 0  0         -b_y/m_eq   kf       -kf;
    0 0 -ke        -ke        -R_m/L_m   0;
    0 0 -ke         ke         0        -R_m/L_m];
B = [zeros(4,2); 1/L_m 0; 0 1/L_m];
C = [1 0 0 0 0 0; 0 1 0 0 0 0];
sys_p = ss(A, B, C, zeros(2,2));
sys_p.StateName  = {'x','y','xdot','ydot','i_L','i_R'};
sys_p.InputName  = {'u_mL','u_mR'};
sys_p.OutputName = {'x','y'};

% Decoupled
Ax = [0 1 0; 0 -b_x/m_eq kf; 0 -2*ke -R_m/L_m];
Ay = [0 1 0; 0 -b_y/m_eq kf; 0 -2*ke -R_m/L_m];
Bi = [0; 0; 1/L_m];
sys_dec_p = ss(blkdiag(Ax, Ay), blkdiag(Bi, Bi), ...
    [1 0 0 0 0 0; 0 0 0 1 0 0], zeros(2,2));
sys_dec_p.StateName  = {'x','xdot','i_x','y','ydot','i_y'};
sys_dec_p.InputName  = {'u_mx','u_my'};
sys_dec_p.OutputName = {'x','y'};
end