function dcm_from_mrp(p)
    p1,p2,p3 = p
    den = (p1^2 + p2^2 + p3^2 + 1)^2
    a = (4*p1^2 + 4*p2^2 + 4*p3^2 - 4)
    [
    (-((8*p2^2+8*p3^2)/den-1)*den)   (8*p1*p2 + p3*a)     (8*p1*p3 - p2*a);
    (8*p1*p2 - p3*a) (-((8*p1^2 + 8*p3^2)/den - 1)*den)   (8*p2*p3 + p1*a);
    (8*p1*p3 + p2*a)  (8*p2*p3 - p1*a)  (-((8*p1^2 + 8*p2^2)/den - 1)*den)
    ]/den
end
function skew(ω::Vector)
    return [0    -ω[3]  ω[2];
            ω[3]  0    -ω[1];
           -ω[2]  ω[1]  0]
end

# Coefficient of lift and drag for the wing (DAE 51 airfoil)
function C_l(α)
    return -7e-6*α^3 - 0.0013*α^2 + 0.0563*α + 0.4683
end

function C_d(α)
    return -4e-6*α^3 - 0.0005*α^2 + 0.0008*α + 0.0269
end

function tiltrotor_dynamics_mrp(model::NamedTuple,x,u)
    # tiltrotor dynamics with an MRP for attitude
    # and velocity in the world frame (not body frame)
    
    r = x[1:3]     # position in world frame 
    v = x[4:6]     # velocity in body frame 
    p = x[7:9]     # n_p_b (MRP) attitude 
    ω = x[10:12]   # angular velocity 
    δ_l = x[13]    # left rotor angle
    δ_r = x[14]    # right rotor angle

    Q = dcm_from_mrp(p) # Rotation matrix from body to world frame

    mass = model.mass
    J = model.J
    gravity = model.gravity
    L = model.L
    kf = model.kf
    km = model.km
    kδ = model.kδ

    w1 = u[1]
    w2 = u[2]

    F_l = max(0,kf*w1)
    F_r = max(0,kf*w2)
    M_l = km*w1
    M_r = -km*w2

    δ_l_dot = kδ*u[3]
    δ_r_dot = kδ*u[4]
    
    # Force due to propellers
    F_thrusters = [F_r*sin(δ_r) + F_l*sin(δ_l); 0; F_r*cos(δ_r) + F_l*cos(δ_l)]

    # Force due to wings
    α = -atan(v[3], v[1]) #Angle of attack
    q = 0.5*model.ρ*(v[1]^2 + v[3]^2)
    L_wing = [0; 0; q*model.S_wing*C_l(α)] #Lift force
    D_wing = [-q*model.S_wing*C_d(α); 0; 0] #Drag force

    F = F_thrusters + L_wing + D_wing

    f = mass*gravity + Q*F # forces in world frame

    M_l = km*w1
    M_r = -km*w2
    # Moments due to propellers
    M_thrusters = [M_r*sin(δ_r) + M_l*sin(δ_l); 0; M_r*cos(δ_r) + M_l*cos(δ_l)]
    
    τ = [L*(-F_r*cos(δ_r) + F_l*cos(δ_l)), 0, (F_r*sin(δ_r) - F_l*sin(δ_l))] + M_thrusters #total rotor torque in body frame

    # this is xdot 
    [
        v
        f/mass
        ((1+norm(p)^2)/4) *(   I + 2*(skew(p)^2 + skew(p))/(1+norm(p)^2)   )*ω
        J\(τ - cross(ω,J*ω))
        δ_l_dot
        δ_r_dot
    ]
end

function rk4(model,ode,x,u,dt)
    # rk4 
    k1 = dt*ode(model,x, u)
    k2 = dt*ode(model,x + k1/2, u)
    k3 = dt*ode(model,x + k2/2, u)
    k4 = dt*ode(model,x + k3, u)
    x + (1/6)*(k1 + 2*k2 + 2*k3 + k4)
end