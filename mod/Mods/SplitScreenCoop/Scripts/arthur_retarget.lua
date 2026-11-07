-- Arthur retarget: SK_Arthur (no locomotion animations exist for SK_Arthur_Skeleton: only 26 cinematic ones) is posed
-- every frame from the animated NPC body (Common_NPC_Skeleton). Same bone names, different reference orientations
-- (NPC Hips local ~identity, Arthur Hips 90 deg about X) and Arthur ~6% taller. Per mapped bone b, parent first, in
-- component space:
--   rotation  qA(b) = qN(b) * inv(qNref(b)) * qAref(b)
--   position  pA(b) = pA(parent) + qA(parent) * (inv(qAref(parent)) * (pAref(b) - pAref(parent)))   (Arthur's lengths)
--   Hips position = NPC Hips position * (Arthur hips height / NPC hips height)
-- Unmapped Arthur bones (face, glasses, CupIn/Middle/Ring/Pinky, twist) keep their local reference pose and follow.
-- UE4SS 3.0.1 zeroes nested structs (FTransform) passed from Lua, so only the flat FRotator / FVector setters are used.
-- Reference rotations captured live from two PoseableMeshComponents in reference pose (2026-11-07).
local REF = {
  Hips = { n = {-0.000000,0.000000,0.030921,-0.999522}, a = {0.707104,-0.001958,-0.001958,-0.707104}, nt = {0.74,0.00,107.08}, at = {0.20,-0.00,113.52} },
  Pelvis = { n = {0.000000,-0.000000,-0.030921,0.999522}, a = {-0.707107,0.000000,0.000000,0.707107}, nt = {0.74,0.00,107.08}, at = {0.20,-0.00,113.52} },
  Spine1 = { n = {0.000000,-0.000000,-0.030921,0.999522}, a = {-0.706894,-0.017352,-0.017352,0.706894}, nt = {0.19,0.00,116.50}, at = {0.35,-0.00,123.57} },
  Spine2 = { n = {-0.000000,0.000000,0.030921,-0.999522}, a = {0.704991,0.054662,0.054662,-0.704991}, nt = {0.29,0.00,127.91}, at = {-0.42,-0.00,139.28} },
  Collar = { n = {0.000000,-0.000000,-0.030921,0.999522}, a = {-0.707012,-0.011585,-0.011585,0.707012}, nt = {-0.82,0.00,139.59}, at = {-3.33,-0.00,157.96} },
  Neck = { n = {-0.000000,0.000000,0.030921,-0.999522}, a = {0.693793,-0.136569,-0.136569,-0.693793}, nt = {-5.14,0.00,158.30}, at = {-3.77,-0.00,171.45} },
  Head = { n = {0.000000,0.000000,-0.030921,0.999522}, a = {-0.706975,0.013631,0.013631,0.706975}, nt = {-0.91,0.00,167.65}, at = {-0.23,-0.00,180.11} },
  Clavicle_L = { n = {0.004232,-0.004605,0.751978,-0.659159}, a = {0.707084,0.005660,-0.698895,-0.107453}, nt = {-6.23,-4.38,147.32}, at = {-5.46,-5.52,163.73} },
  Arm_L = { n = {0.356120,0.351398,-0.660287,0.560107}, a = {-0.626328,-0.328198,0.555476,0.437545}, nt = {-7.44,-16.76,145.52}, at = {-6.85,-15.09,162.16} },
  Elbow_L = { n = {-0.383107,-0.285627,0.592713,-0.648335}, a = {0.577489,0.408052,-0.608480,-0.360211}, nt = {-10.60,-29.76,122.58}, at = {-9.14,-27.33,134.34} },
  Wrist_L = { n = {0.472866,-0.068929,0.039331,0.877553}, a = {-0.577489,-0.408052,0.608480,0.360211}, nt = {-7.21,-43.63,101.78}, at = {-8.13,-39.75,106.53} },
  Clavicle_R = { n = {0.751978,-0.659159,-0.004232,0.004605}, a = {0.698895,0.107452,0.707084,0.005660}, nt = {-6.23,4.38,147.32}, at = {-5.46,5.52,163.73} },
  Arm_R = { n = {-0.660287,0.560107,-0.356120,-0.351398}, a = {-0.555476,-0.437545,-0.626328,-0.328197}, nt = {-7.44,16.76,145.52}, at = {-6.85,15.09,162.16} },
  Elbow_R = { n = {0.592712,-0.648335,0.383107,0.285627}, a = {0.608480,0.360211,0.577489,0.408052}, nt = {-10.60,29.75,122.58}, at = {-9.14,27.33,134.34} },
  Wrist_R = { n = {0.039331,0.877553,-0.472866,0.068929}, a = {-0.608480,-0.360211,-0.577489,-0.408052}, nt = {-7.21,43.62,101.78}, at = {-8.13,39.75,106.53} },
  Leg_L = { n = {0.000000,-0.000000,0.030921,-0.999522}, a = {-0.000103,-0.689944,0.723863,-0.000108}, nt = {-0.00,-11.44,95.88}, at = {0.55,-7.82,103.38} },
  Knee_L = { n = {-0.000000,-0.000000,-0.117917,0.993023}, a = {-0.046079,0.690317,-0.720435,-0.048089}, nt = {1.94,-10.44,56.83}, at = {0.56,-9.89,63.14} },
  Ankle_L = { n = {0.000000,-0.000000,0.117917,-0.993023}, a = {-0.072746,-0.701201,0.706286,0.064696}, nt = {-5.82,-11.75,11.78}, at = {-6.09,-12.01,13.57} },
  Heel_L = { n = {0.012168,0.164598,-0.133375,0.977226}, a = {0.522011,0.476974,-0.545858,0.449487}, nt = {-9.68,-11.05,4.73}, at = {-10.43,-12.16,2.24} },
  Ball_L = { n = {-0.000644,-0.008703,0.135225,-0.990776}, a = {-0.522011,-0.476974,0.545858,-0.449487}, nt = {8.11,-14.92,0.58}, at = {5.97,-14.50,1.39} },
  Toe_L = { n = {0.096074,0.706739,-0.095163,0.694431}, a = {0.522011,0.476974,-0.545858,0.449487}, nt = {14.49,-16.27,0.49}, at = {15.26,-15.82,0.91} },
  Leg_R = { n = {0.000000,-0.000000,0.030921,-0.999522}, a = {0.723863,-0.000108,0.000103,0.689944}, nt = {-0.00,11.44,95.88}, at = {0.55,7.82,103.38} },
  Knee_R = { n = {0.000000,-0.000000,0.056311,0.998413}, a = {-0.720435,-0.048089,0.046079,-0.690317}, nt = {1.94,10.44,56.83}, at = {0.56,9.89,63.14} },
  Ankle_R = { n = {-0.000000,-0.000000,-0.056311,-0.998413}, a = {0.720435,0.048089,-0.046079,0.690317}, nt = {-5.82,11.75,11.78}, at = {-6.09,12.01,13.57} },
  Heel_R = { n = {-0.022319,0.163532,0.072716,0.983601}, a = {-0.545858,0.449487,-0.522011,-0.476974}, nt = {-9.68,11.05,4.73}, at = {-10.43,12.16,2.24} },
  Ball_R = { n = {0.001180,-0.008646,-0.073724,-0.997240}, a = {0.545858,-0.449487,0.522011,0.476974}, nt = {8.14,14.75,0.58}, at = {5.97,14.50,1.39} },
  Toe_R = { n = {-0.699042,-0.051296,0.711269,-0.052965}, a = {-0.545858,0.449487,-0.522011,-0.476974}, nt = {14.52,16.11,0.49}, at = {15.26,15.82,0.91} },
  IndexA_L = { n = {0.641189,-0.548646,-0.393580,-0.364635}, a = {-0.592708,-0.428549,0.552622,0.399565}, nt = {-2.84,-51.99,92.46}, at = {-3.72,-45.98,97.22} },
  IndexB_L = { n = {-0.592404,0.503742,0.463774,0.424518}, a = {0.527094,0.504003,-0.494525,-0.472861}, nt = {-2.38,-53.34,89.90}, at = {-3.44,-47.30,93.23} },
  IndexC_L = { n = {0.512296,-0.455080,-0.552445,-0.474615}, a = {-0.476063,-0.550574,0.448516,0.518715}, nt = {-2.18,-54.14,87.11}, at = {-3.25,-47.43,90.27} },
  ThumbA_L = { n = {0.779274,-0.102830,-0.614454,0.067853}, a = {-0.133655,-0.694360,0.647369,-0.284452}, nt = {-3.52,-45.38,97.17}, at = {-4.92,-41.47,101.82} },
  ThumbB_L = { n = {-0.773736,0.103433,0.621413,-0.066929}, a = {0.174861,0.685145,-0.707077,0.006457}, nt = {-2.37,-46.23,94.28}, at = {-3.00,-41.03,98.96} },
  ThumbC_L = { n = {0.701724,-0.110086,-0.701716,0.055308}, a = {-0.016378,-0.672646,0.739564,-0.018007}, nt = {-1.54,-47.24,90.81}, at = {-2.06,-41.26,95.32} },
  IndexA_R = { n = {-0.393579,-0.364635,-0.641189,0.548646}, a = {-0.552622,-0.399565,-0.592708,-0.428549}, nt = {-2.84,51.99,92.46}, at = {-3.72,45.98,97.22} },
  IndexB_R = { n = {0.463774,0.424518,0.592404,-0.503742}, a = {0.494525,0.472861,0.527094,0.504003}, nt = {-2.38,53.34,89.90}, at = {-3.44,47.30,93.23} },
  IndexC_R = { n = {-0.552444,-0.474615,-0.512296,0.455080}, a = {-0.448516,-0.518715,-0.476063,-0.550574}, nt = {-2.18,54.14,87.11}, at = {-3.25,47.43,90.27} },
  ThumbA_R = { n = {-0.614453,0.067853,-0.779275,0.102830}, a = {-0.647369,0.284453,-0.133655,-0.694360}, nt = {-3.52,45.38,97.17}, at = {-4.92,41.47,101.82} },
  ThumbB_R = { n = {0.621413,-0.066929,0.773737,-0.103434}, a = {0.707077,-0.006457,0.174861,0.685145}, nt = {-2.37,46.23,94.28}, at = {-3.00,41.03,98.96} },
  ThumbC_R = { n = {-0.701716,0.055308,-0.701724,0.110087}, a = {-0.739564,0.018007,-0.016378,-0.672646}, nt = {-1.54,47.24,90.81}, at = {-2.06,41.26,95.32} },
}
local PARENT = {
    Pelvis = "Hips", Spine1 = "Hips", Spine2 = "Spine1", Collar = "Spine2", Neck = "Collar", Head = "Neck",
    Clavicle_L = "Collar", Arm_L = "Clavicle_L", Elbow_L = "Arm_L", Wrist_L = "Elbow_L",
    Clavicle_R = "Collar", Arm_R = "Clavicle_R", Elbow_R = "Arm_R", Wrist_R = "Elbow_R",
    Leg_L = "Pelvis", Knee_L = "Leg_L", Ankle_L = "Knee_L", Heel_L = "Ankle_L", Ball_L = "Heel_L", Toe_L = "Ball_L",
    Leg_R = "Pelvis", Knee_R = "Leg_R", Ankle_R = "Knee_R", Heel_R = "Ankle_R", Ball_R = "Heel_R", Toe_R = "Ball_R",
}
local ORDER = { "Hips", "Pelvis", "Spine1", "Spine2", "Collar", "Neck", "Head",
    "Clavicle_L", "Arm_L", "Elbow_L", "Wrist_L", "Clavicle_R", "Arm_R", "Elbow_R", "Wrist_R",
    "Leg_L", "Knee_L", "Ankle_L", "Heel_L", "Ball_L", "Toe_L", "Leg_R", "Knee_R", "Ankle_R", "Heel_R", "Ball_R", "Toe_R" }

local function qmul(a, b)
    return { a[4] * b[1] + a[1] * b[4] + a[2] * b[3] - a[3] * b[2],
             a[4] * b[2] - a[1] * b[3] + a[2] * b[4] + a[3] * b[1],
             a[4] * b[3] + a[1] * b[2] - a[2] * b[1] + a[3] * b[4],
             a[4] * b[4] - a[1] * b[1] - a[2] * b[2] - a[3] * b[3] }
end
local function qinv(a) return { -a[1], -a[2], -a[3], a[4] } end
local function qrot(q, v)
    local p = qmul(qmul(q, { v[1], v[2], v[3], 0 }), qinv(q))
    return { p[1], p[2], p[3] }
end
local DEG = 180 / math.pi
local function q2r(q) -- FQuat -> FRotator (UE's FQuat::Rotator)
    local x, y, z, w = q[1], q[2], q[3], q[4]
    local sing = z * x - w * y
    local yaw = math.atan(2 * (w * z + x * y), 1 - 2 * (y * y + z * z)) * DEG
    local pitch, roll
    if sing < -0.4999995 then
        pitch = -90; roll = -yaw - 2 * math.atan(x, w) * DEG
    elseif sing > 0.4999995 then
        pitch = 90; roll = yaw - 2 * math.atan(x, w) * DEG
    else
        pitch = math.asin(2 * sing) * DEG
        roll = math.atan(-2 * (w * x + y * z), 1 - 2 * (x * x + y * y)) * DEG
    end
    return { Pitch = pitch, Yaw = yaw, Roll = roll }
end

local OFF, LOCALT, FN = {}, {}, {}
for _, b in ipairs(ORDER) do
    local r = REF[b]
    OFF[b] = qmul(qinv(r.n), r.a)
    local par = PARENT[b]
    if par then
        local pr = REF[par]
        LOCALT[b] = qrot(qinv(pr.a), { r.at[1] - pr.at[1], r.at[2] - pr.at[2], r.at[3] - pr.at[3] })
    end
end
local HIPS_K = REF.Hips.at[3] / REF.Hips.nt[3]

local M = {}

-- npc: the animated NPC SkeletalMeshComponent; pose: the Arthur PoseableMeshComponent. Component space (2) reads
-- are independent of the NPC component's own (tiny) scale.
function M.apply(npc, pose)
    for _, b in ipairs(ORDER) do FN[b] = FN[b] or FName(b) end
    local qa, pa = {}, {}
    for _, b in ipairs(ORDER) do
        local t = npc:GetSocketTransform(FN[b], 2)
        local q = qmul({ t.Rotation.X, t.Rotation.Y, t.Rotation.Z, t.Rotation.W }, OFF[b])
        local pos
        if b == "Hips" then
            pos = { t.Translation.X * HIPS_K, t.Translation.Y * HIPS_K, t.Translation.Z * HIPS_K }
        else
            local par = PARENT[b]
            local d = qrot(qa[par], LOCALT[b])
            pos = { pa[par][1] + d[1], pa[par][2] + d[2], pa[par][3] + d[3] }
        end
        qa[b], pa[b] = q, pos
        pose:SetBoneRotationByName(FN[b], q2r(q), 1)
        pose:SetBoneLocationByName(FN[b], { X = pos[1], Y = pos[2], Z = pos[3] }, 1)
    end
end

return M
