local vc = game:GetService("VoiceChatService")
local vi = game:GetService("VoiceChatInternal")
local gid = vi:GetGroupId()
vi:JoinByGroupId(gid,false)
vc:leaveVoice()
task.wait()
for i = 1, 4 do
    vi:JoinByGroupId(gid,false)
end
task.wait(5)
vc:joinVoice()
vi:JoinByGroupId(gid,false) 
