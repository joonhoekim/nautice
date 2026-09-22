# Claude Code 에 물리기

**먼저 [`README.md`](../README.md) 의 "에이전트에 물리기" 를 본다.** 거기 있는
프롬프트를 붙여 넣으면 에이전트가 이 문서의 내용을 스스로 확인하고, 어느
방식으로 어디에 넣을지 물어본 뒤 설정한다. 이 문서는 직접 고칠 때의 참고다.

대상은 `~/.claude/` (Windows 는 `C:\Users\<user>\.claude\`). 프로젝트에만
걸려면 같은 이름을 저장소의 `.claude/` 아래에 둔다.

## 1. 훅 — 자동으로 울리게 하기

`settings.json`. **`-a` 가 없으면 소리가 끝날 때까지 에이전트가 멈춘다.**

```json
{
  "hooks": {
    "Notification": [
      { "matcher": "", "hooks": [{ "type": "command", "command": "nautice call -a -q" }] }
    ],
    "Stop": [
      { "matcher": "", "hooks": [{ "type": "command", "command": "nautice say -a -q '작업이 끝났습니다'" }] }
    ]
  }
}
```

`Notification` 은 Claude 가 사람을 기다릴 때(권한 요청, 입력 대기) 울리고,
`Stop` 은 한 턴을 마쳤을 때 울린다. Windows 에서는 `nautice.cmd` 로 적는다.

자리를 비울 때가 많으면 `-c both` 를 붙인다. 소리는 그 순간에만 들리지만
배너는 알림 센터에 남아서 돌아와서 볼 수 있다.

```json
{ "type": "command", "command": "nautice call -a -q -c both" }
```

## 2. 훅 없이, 에이전트가 판단해서 부르게 하기

훅은 무조건 울린다. 필요할 때만 부르게 하려면 훅을 걸지 말고 `CLAUDE.md` 에
도구의 존재만 알린다.

```markdown
## 사용 가능한 도구

- `nautice` — 사람을 소리로 부르는 알림 CLI. `nautice call -a -q` 로 부른다.
  자동으로 울리지는 않는다 — 오래 걸리는 작업이 끝났거나 사람의 판단이
  필요할 때만 쓴다.
```

"자동으로 울리지 않는다" 를 적어야 Claude 가 아무 때나 소리를 내지 않는다.

## 3. 커밋·PR 에 도구 표기 끄기

`settings.json`. 빈 문자열이 "붙이지 않음" 을 뜻한다.

```json
{
  "attribution": { "commit": "", "pr": "" }
}
```

`includeCoAuthoredBy: false` 로도 같은 효과를 내지만 그쪽은 deprecated 다.
