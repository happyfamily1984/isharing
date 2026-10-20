# 아이콘 SVG 생성: full(둥근 사각 배경 포함), fg(적응형 전경, 투명), bg(적응형 배경)
PIN = "M0,2.25 C-0.4,1.65 -1,1.05 -1,0 A1,1 0 1 1 1,0 C1,1.05 0.4,1.65 0,2.25 Z"

def pin(x, y, r, color, dark, extra=""):
    return f'''
  <g transform="translate({x},{y}) scale({r})">
    <ellipse cx="0" cy="2.3" rx="0.55" ry="0.16" fill="#000" opacity="0.13"/>
    <path d="{PIN}" fill="{color}"/>
    <path d="{PIN}" fill="none" stroke="{dark}" stroke-width="0.07" opacity="0.35"/>
    <circle cx="0" cy="0" r="0.68" fill="#fff"/>
    <circle cx="-0.25" cy="-0.05" r="0.1" fill="#3b2f2f"/>
    <circle cx="0.25" cy="-0.05" r="0.1" fill="#3b2f2f"/>
    <circle cx="-0.21" cy="-0.09" r="0.035" fill="#fff"/>
    <circle cx="0.29" cy="-0.09" r="0.035" fill="#fff"/>
    <ellipse cx="-0.43" cy="0.17" rx="0.12" ry="0.07" fill="#ff8fa3" opacity="0.8"/>
    <ellipse cx="0.43" cy="0.17" rx="0.12" ry="0.07" fill="#ff8fa3" opacity="0.8"/>
    <path d="M-0.15,0.17 Q0,0.33 0.15,0.17" fill="none" stroke="#3b2f2f" stroke-width="0.07" stroke-linecap="round"/>
    {extra}
  </g>'''

# 아빠: 파랑, 눈썹 / 엄마: 코랄, 리본 / 아이: 노랑, 머리카락 한 가닥
dad_extra = '<path d="M-0.37,-0.24 Q-0.26,-0.33 -0.14,-0.27 M0.14,-0.27 Q0.26,-0.33 0.37,-0.24" stroke="#3b2f2f" stroke-width="0.06" stroke-linecap="round"/>'
mom_extra = '<g transform="translate(0.62,-0.72) rotate(20)"><path d="M0,0 L-0.32,-0.2 L-0.32,0.2 Z M0,0 L0.32,-0.2 L0.32,0.2 Z" fill="#ff4d79"/><circle r="0.09" fill="#e0315f"/></g>'
kid_extra = '<path d="M0,-1 Q0.12,-1.35 0.34,-1.28" fill="none" stroke="#e0a400" stroke-width="0.12" stroke-linecap="round"/>'

def pins(scale=1.0, cx=512, cy=512):
    # 1024 캔버스 기준 배치. scale 로 적응형 아이콘 안전 영역에 맞춘다.
    def t(x, y, r):
        return cx + (x - 512) * scale, cy + (y - 512) * scale, r * scale
    return (pin(*t(330, 430, 120), "#5b8def", "#2e5fc4", dad_extra)
          + pin(*t(694, 430, 120), "#ff7a8a", "#d94a5c", mom_extra)
          + pin(*t(512, 540, 95), "#ffcc33", "#d9a300", kid_extra))

ground = '''
  <ellipse cx="512" cy="820" rx="420" ry="120" fill="#bfe8c9"/>
  <path d="M150,800 Q512,700 874,800" fill="none" stroke="#fff" stroke-width="18" stroke-linecap="round" opacity="0.8" stroke-dasharray="40 34"/>'''

bg_grad = '''<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#fff6e5"/><stop offset="1" stop-color="#ffe3c2"/></linearGradient></defs>'''

def svg(body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">{body}</svg>'

open("full.svg", "w").write(svg(bg_grad + '<rect width="1024" height="1024" rx="0" fill="url(#g)"/>' + ground + pins(scale=1.1, cy=500)))
open("round.svg", "w").write(svg(bg_grad + '<rect x="0" y="0" width="1024" height="1024" rx="230" fill="url(#g)"/>' + ground + pins(scale=1.1, cy=500)))
# 적응형: 전경은 가운데 66/108 안전 영역 안에 들어가게 줄인다
open("fg.svg", "w").write(svg(pins(scale=0.78, cy=500)))
open("bg.svg", "w").write(svg(bg_grad + '<rect width="1024" height="1024" fill="url(#g)"/>' + ground.replace('cy="820"', 'cy="760"').replace("M150,800 Q512,700 874,800", "M150,740 Q512,640 874,740")))
