import discord
from discord.ext import commands
from discord.ui import Button, View
import json
import asyncio
from datetime import datetime, timedelta
import os
import re
import locale

# 로케일 설정 (숫자 포매팅용)
locale.setlocale(locale.LC_ALL, 'ko_KR.UTF-8')

# 배팅 시스템 설정
ALLOWED_ROLE_IDS = [1385795561117978706, 1390999677104689183]
ADMIN_USER_IDS = [1372058115863740446, 376915764416086017]  # 버튼 사용 가능한 관리자 ID
RESTRICTED_ROLE_IDS = [1390999677104689183, 1392003021579489341]
BETTING_OPEN_DURATION = 60  # 초 단위
ROBBER_WIN_MULTIPLIER = 2.0
POLICE_WIN_MULTIPLIER = 1.3
LOL_MULTIPLIER = 1.95
MIN_BET_AMOUNT = 100000000  # 1억원
MAX_BET_AMOUNT = 10000000000  # 100억원
BETS_FILE = "bets.json"
COOLDOWN_TIME = 60  # 1분 쿨다운 (초 단위)

# 음성 채널 설정
VOICE_CHANNEL_ID = 1395980597683556464  # 사용자가 클릭하는 음성 채널 ID
CATEGORY_ID = 1395955353736319126  # 생성될 카테고리 ID
VOICE_CHANNEL_PREFIX = "🎤ㆍ "  # 생성될 음성 채널 접두사

# 봇 설정
intents = discord.Intents.default()
intents.messages = True
intents.message_content = True
intents.members = True
intents.voice_states = True

bot = commands.Bot(command_prefix='!', intents=intents)

# 쿨다운 저장 변수
cooldowns = {}

## ----------------------------
## 버튼 UI 클래스
## ----------------------------

class BettingButtons(View):
    def __init__(self):
        super().__init__(timeout=None)
        
    async def interaction_check(self, interaction: discord.Interaction) -> bool:
        # 쿨다운 확인
        current_time = datetime.now().timestamp()
        last_used = cooldowns.get(interaction.user.id, 0)
        
        if current_time - last_used < COOLDOWN_TIME:
            remaining = int(COOLDOWN_TIME - (current_time - last_used))
            await interaction.response.send_message(
                f"🚫 쿨다운 중입니다. {remaining}초 후에 다시 시도해주세요.",
                ephemeral=True
            )
            return False
            
        if interaction.user.id not in ADMIN_USER_IDS:
            await interaction.response.send_message("🚫 이 버튼을 사용할 권한이 없습니다.", ephemeral=True)
            return False
            
        if not interaction.user.voice or not interaction.user.voice.channel:
            await interaction.response.send_message("❌ 음성 채널에 접속한 상태에서만 사용할 수 있습니다.", ephemeral=True)
            return False
            
        return True
        
    @discord.ui.button(label="RP 이벤트 시작", style=discord.ButtonStyle.primary, custom_id="rp_event")
    async def rp_event_button(self, interaction: discord.Interaction, button: Button):
        # 쿨다운 적용
        cooldowns[interaction.user.id] = datetime.now().timestamp()
        
        voice_channel = interaction.user.voice.channel
        
        starting_embed = discord.Embed(
            title="🕶️ **익명 RP 이벤트 시작**",
            description=f"관리자에 의해 익명 RP 이벤트가 시작되었습니다! (최소 {format_krw(MIN_BET_AMOUNT)} ~ 최대 {format_krw(MAX_BET_AMOUNT)})\n\n⚠️ RP 중 재알 발생 시 모든 배팅은 패알(업장승리) 처리됩니다.",
            color=0x7289da,
            timestamp=datetime.now()
        )
        starting_embed.set_footer(text=f"시작한 관리자: {interaction.user.display_name}")
        
        # 응답 전송
        await interaction.response.send_message(embed=starting_embed)
        
        ctx = await bot.get_context(interaction.message)
        ctx.author = interaction.user
        await start_betting(ctx, "rp", voice_channel)

    @discord.ui.button(label="도주 RP 시작", style=discord.ButtonStyle.green, custom_id="escape_event")
    async def escape_event_button(self, interaction: discord.Interaction, button: Button):
        cooldowns[interaction.user.id] = datetime.now().timestamp()
        voice_channel = interaction.user.voice.channel
        
        starting_embed = discord.Embed(
            title="🏃‍♂️ **익명 도주RP 이벤트 시작**",
            description=f"관리자에 의해 익명 도주RP 이벤트가 시작되었습니다! (최소 {format_krw(MIN_BET_AMOUNT)} ~ 최대 {format_krw(MAX_BET_AMOUNT)})\n\n⚠️ RP 중 재알 발생 시 모든 배팅은 패알(업장승리) 처리됩니다.",
            color=0x7289da,
            timestamp=datetime.now()
        )
        starting_embed.set_footer(text=f"시작한 관리자: {interaction.user.display_name}")
        
        await interaction.response.send_message(embed=starting_embed)
        
        ctx = await bot.get_context(interaction.message)
        ctx.author = interaction.user
        await start_betting(ctx, "escape", voice_channel)
        
    @discord.ui.button(label="롤 배팅 시작", style=discord.ButtonStyle.red, custom_id="lol_event")
    async def lol_event_button(self, interaction: discord.Interaction, button: Button):
        cooldowns[interaction.user.id] = datetime.now().timestamp()
        voice_channel = interaction.user.voice.channel
        
        starting_embed = discord.Embed(
            title="🎮 **리그 오브 레전드 배팅 시작**",
            description=f"관리자에 의해 리그 오브 레전드 배팅이 시작되었습니다! (최소 {format_krw(MIN_BET_AMOUNT)} ~ 최대 {format_krw(MAX_BET_AMOUNT)})\n\n양측 배당률: 1.95배",
            color=0x7289da,
            timestamp=datetime.now()
        )
        starting_embed.add_field(
            name="🔵 블루팀 (강도측)",
            value="`!강도 [금액]` 명령어로 배팅",
            inline=True
        )
        starting_embed.add_field(
            name="🔴 레드팀 (경찰측)",
            value="`!경찰 [금액]` 명령어로 배팅",
            inline=True
        )
        starting_embed.set_footer(text=f"시작한 관리자: {interaction.user.display_name}")
        
        await interaction.response.send_message(embed=starting_embed)
        
        ctx = await bot.get_context(interaction.message)
        ctx.author = interaction.user
        await start_betting(ctx, "lol", voice_channel)

class ResultButtons(View):
    def __init__(self):
        super().__init__(timeout=None)
        
    async def interaction_check(self, interaction: discord.Interaction) -> bool:
        bets_data = load_bets()
        if not bets_data.get('starter_id'):
            await interaction.response.send_message("⚠️ 처리할 배팅이 없습니다.", ephemeral=True)
            return False
            
        if interaction.user.id not in [bets_data.get('starter_id')] + ADMIN_USER_IDS:
            await interaction.response.send_message("🚫 결과 처리는 배팅을 시작한 유저나 관리자만 가능합니다.", ephemeral=True)
            return False
            
        return True
        
    @discord.ui.button(label="강도측 승리", style=discord.ButtonStyle.primary, custom_id="robber_win")
    async def robber_win_button(self, interaction: discord.Interaction, button: Button):
        await interaction.response.defer()
        ctx = await bot.get_context(interaction.message)
        ctx.author = interaction.user
        await process_result(ctx, "강도측")
        
    @discord.ui.button(label="경찰측 승리", style=discord.ButtonStyle.green, custom_id="police_win")
    async def police_win_button(self, interaction: discord.Interaction, button: Button):
        await interaction.response.defer()
        ctx = await bot.get_context(interaction.message)
        ctx.author = interaction.user
        await process_result(ctx, "보안관 및 경찰측")
        
    @discord.ui.button(label="무효 처리", style=discord.ButtonStyle.red, custom_id="invalidate")
    async def invalidate_button(self, interaction: discord.Interaction, button: Button):
        await interaction.response.defer()
        ctx = await bot.get_context(interaction.message)
        ctx.author = interaction.user
        await invalidate_bets(ctx)

## ----------------------------
## 공통 유틸리티 함수
## ----------------------------

def format_krw(amount):
    """숫자를 한국어 금액 표현으로 변환 (KRW 표시 추가)"""
    amount = int(amount)
    krw_formatted = locale.format_string("%d", amount, grouping=True)
    
    if amount == 0:
        return "0원 (KRW 0)"
    
    units = ['', '만', '억']
    unit_size = 10000
    result = []
    
    for unit in units:
        if amount <= 0:
            break
        amount, mod = divmod(amount, unit_size)
        if mod > 0:
            result.append(f"{mod}{unit}")
    
    return ' '.join(reversed(result)) + f"원 (KRW {krw_formatted})"

def korean_to_number(text):
    """한국어 금액을 숫자로 변환 + 유효성 검사"""
    text = text.replace(',', '').replace(' ', '').replace('배팅', '').strip().lower()
    
    # 숫자만 있는 경우
    if text.isdigit():
        num = int(text)
        if num < MIN_BET_AMOUNT:
            raise ValueError(f"최소 배팅 금액은 {format_krw(MIN_BET_AMOUNT)} 입니다")
        if num > MAX_BET_AMOUNT:
            raise ValueError(f"최대 배팅 금액은 {format_krw(MAX_BET_AMOUNT)} 입니다")
        return num
    
    # 한글 단위 포함 처리
    total = 0
    current_num = 0
    unit_map = {'억': 100000000, '만': 10000, '천': 1000, '백': 100, '십': 10}
    
    i = 0
    while i < len(text):
        if text[i].isdigit():
            num_str = ''
            while i < len(text) and text[i].isdigit():
                num_str += text[i]
                i += 1
            current_num = int(num_str)
        else:
            unit = text[i]
            if unit in unit_map:
                if unit == '억':  # 대단위 처리
                    if current_num == 0:
                        current_num = 1
                    total += current_num * unit_map[unit]
                    current_num = 0
                else:  # 소단위 처리 (천, 백, 십)
                    if current_num == 0:
                        current_num = 1
                    total += current_num * unit_map[unit]
                    current_num = 0
            i += 1
    
    total += current_num  # 남은 숫자 처리
    
    # 금액 검사
    if total < MIN_BET_AMOUNT:
        raise ValueError(f"최소 배팅 금액은 {format_krw(MIN_BET_AMOUNT)} 입니다")
    if total > MAX_BET_AMOUNT:
        raise ValueError(f"최대 배팅 금액은 {format_krw(MAX_BET_AMOUNT)} 입니다")
    
    return total

## ----------------------------
## 배팅 시스템 함수
## ----------------------------

def init_bets_file():
    """배팅 데이터 초기화"""
    if not os.path.exists(BETS_FILE):
        with open(BETS_FILE, 'w') as f:
            json.dump({
                "active": False, 
                "bets": {}, 
                "starter_id": None, 
                "event_type": None, 
                "voice_channel_id": None,
                "winning_team": None,
                "total_bets": 0,
                "total_payout": 0
            }, f)

def load_bets():
    """배팅 데이터 로드"""
    if not os.path.exists(BETS_FILE):
        init_bets_file()
    with open(BETS_FILE, 'r') as f:
        return json.load(f)

def save_bets(data):
    """배팅 데이터 저장"""
    with open(BETS_FILE, 'w') as f:
        json.dump(data, f, indent=4)

async def set_channel_permissions(channel, allow_send_messages):
    """채널 권한 설정 (보기 권한은 유지, 메시지 전송만 제어)"""
    # 기본 역할에 대한 권한 설정
    default_overwrite = channel.overwrites_for(channel.guild.default_role)
    default_overwrite.send_messages = allow_send_messages
    await channel.set_permissions(channel.guild.default_role, overwrite=default_overwrite)
    
    # 특정 역할에 대한 권한 설정
    for role_id in RESTRICTED_ROLE_IDS:
        role = channel.guild.get_role(role_id)
        if role:
            role_overwrite = channel.overwrites_for(role)
            role_overwrite.send_messages = allow_send_messages
            await channel.set_permissions(role, overwrite=role_overwrite)

async def start_betting(ctx, event_type, voice_channel):
    """배팅 시작 함수"""
    # 기존 데이터 완전 삭제
    bets_data = {
        'active': True,
        'bets': {},
        'start_time': datetime.now().isoformat(),
        'starter_id': ctx.author.id,
        'event_type': event_type,
        'voice_channel_id': voice_channel.id,
        'winning_team': None,
        'total_bets': 0,
        'total_payout': 0
    }
    save_bets(bets_data)

    # 채팅 권한 활성화 (보기 권한은 유지)
    await set_channel_permissions(voice_channel, True)

    if event_type == "rp":
        embed = discord.Embed(
            title="🎲 **익명의 RP 이벤트 시작!** 🎲",
            description=f"아래 팀을 선택하여 배팅을 진행해주세요. (최소 {format_krw(MIN_BET_AMOUNT)} ~ 최대 {format_krw(MAX_BET_AMOUNT)})\n60초 후 자동으로 배팅이 마감됩니다.\n\n⚠️ RP 중 재알 발생 시 모든 배팅은 패알(업장승리) 처리됩니다.",
            color=0x00ff00,
            timestamp=datetime.now()
        )
        embed.add_field(
            name="🔫 **강도측 승리** (2.0배)",
            value="`!강도 [금액]` 명령어로 배팅\n예: `!강도 1억`, `!강도 3억7천500만`",
            inline=False
        )
        embed.add_field(
            name="👮 **보안관 및 경찰측 승리** (1.3배)",
            value="`!경찰 [금액]` 명령어로 배팅\n예: `!경찰 1억`, `!경찰 12억3천450만`",
            inline=False
        )
        
    elif event_type == "lol":
        embed = discord.Embed(
            title="🎮 **리그 오브 레전드 배팅 시작!** 🎮",
            description=f"아래 팀을 선택하여 배팅을 진행해주세요. (최소 {format_krw(MIN_BET_AMOUNT)} ~ 최대 {format_krw(MAX_BET_AMOUNT)})\n60초 후 자동으로 배팅이 마감됩니다.\n\n양측 배당률: 1.95배",
            color=0x00ff00,
            timestamp=datetime.now()
        )
        embed.add_field(
            name="🔵 **블루팀 (강도측)** (1.95배)",
            value="`!강도 [금액]` 명령어로 배팅\n예: `!강도 1억`, `!강도 3억7천500만`",
            inline=False
        )
        embed.add_field(
            name="🔴 **레드팀 (경찰측)** (1.95배)",
            value="`!경찰 [금액]` 명령어로 배팅\n예: `!경찰 1억`, `!경찰 12억3천450만`",
            inline=False
        )
        
    elif event_type == "escape":
        embed = discord.Embed(
            title="🏃‍♂️ **익명의 도주RP 이벤트 시작!** 🏃‍♂️",
            description=f"아래 팀을 선택하여 배팅을 진행해주세요. (최소 {format_krw(MIN_BET_AMOUNT)} ~ 최대 {format_krw(MAX_BET_AMOUNT)})\n60초 후 자동으로 배팅이 마감됩니다.\n\n⚠️ RP 중 재알 발생 시 모든 배팅은 패알(업장승리) 처리됩니다.",
            color=0x00ff00,
            timestamp=datetime.now()
        )
        embed.add_field(
            name="🏃‍♂️ **도주측 승리** (2.0배)",
            value="`!강도 [금액]` 명령어로 배팅\n예: `!강도 1억`, `!강도 3억7천500만`",
            inline=False
        )
        embed.add_field(
            name="👮 **추격측 승리** (1.3배)",
            value="`!경찰 [금액]` 명령어로 배팅\n예: `!경찰 1억`, `!경찰 12억3천450만`",
            inline=False
        )
    
    embed.set_footer(text="배팅 마감까지 60초 남음", icon_url="https://i.imgur.com/7WgqD5W.png")
    embed.set_thumbnail(url="https://i.imgur.com/3Jm8W9x.png")
    msg = await voice_channel.send(embed=embed)
    
    for i in range(BETTING_OPEN_DURATION, 0, -5):
        bets_data = load_bets()
        if not bets_data['active']:
            break
            
        remaining = timedelta(seconds=i)
        embed.set_footer(text=f"배팅 마감까지 {remaining.seconds}초 남음", icon_url="https://i.imgur.com/7WgqD5W.png")
        await msg.edit(embed=embed)
        await asyncio.sleep(5)
    
    bets_data = load_bets()
    if bets_data['active']:
        bets_data['active'] = False
        save_bets(bets_data)
        embed.set_footer(text="⏰ 배팅이 마감되었습니다!", icon_url="https://i.imgur.com/7WgqD5W.png")
        await msg.edit(embed=embed)
        
        # 채팅 권한 비활성화 (보기 권한은 유지)
        channel = ctx.guild.get_channel(bets_data['voice_channel_id'])
        await set_channel_permissions(channel, False)
        
        close_embed = discord.Embed(
            title="📢 **배팅 마감 알림**",
            description="모든 배팅이 마감되었습니다.\n결과 발표를 기다려주세요!",
            color=0xff0000,
            timestamp=datetime.now()
        )
        close_embed.set_thumbnail(url="https://i.imgur.com/3Jm8W9x.png")
        await voice_channel.send(embed=close_embed)
        
        # 결과 처리 버튼 표시
        result_embed = discord.Embed(
            title="📢 **결과 처리 준비**",
            description="아래 버튼을 눌러 결과를 처리하세요.",
            color=0x7289da,
            timestamp=datetime.now()
        )
        await voice_channel.send(embed=result_embed, view=ResultButtons())

async def calculate_profit_loss(ctx):
    """업장의 최종 손익을 계산하고 표시하는 함수"""
    bets_data = load_bets()
    
    if not bets_data.get('bets'):
        no_data_embed = discord.Embed(
            title="ℹ️ 데이터 없음",
            description="분석할 배팅 데이터가 없습니다.",
            color=0x7289da
        )
        await ctx.send(embed=no_data_embed)
        return
    
    winning_team = bets_data.get('winning_team')
    
    if not winning_team:
        no_result_embed = discord.Embed(
            title="⚠️ 결과 미처리",
            description="아직 결과가 처리되지 않은 배팅입니다.",
            color=0xffcc00
        )
        await ctx.send(embed=no_result_embed)
        return
    
    total_bets = bets_data.get('total_bets', 0)
    total_payout = bets_data.get('total_payout', 0)
    profit_loss = total_bets - total_payout
    
    event_type = bets_data.get('event_type', 'rp')
    
    if event_type == "rp":
        team1_name = "강도측"
        team2_name = "보안관 및 경찰측"
    elif event_type == "lol":
        team1_name = "블루팀 (강도측)"
        team2_name = "레드팀 (경찰측)"
    elif event_type == "escape":
        team1_name = "도주측"
        team2_name = "추격측"
    
    result_embed = discord.Embed(
        title="💰 **업장 최종 손익 결과** 💰",
        color=0x7289da if profit_loss >= 0 else 0xff0000,
        timestamp=datetime.now()
    )
    
    result_embed.add_field(
        name="📊 총 배팅 금액",
        value=f"{format_krw(total_bets)}",
        inline=False
    )
    
    if winning_team == "무효":
        result_embed.add_field(
            name="⚠️ 무효 처리",
            value="재알 발생으로 모든 배팅이 패알 처리되었습니다.",
            inline=False
        )
    else:
        result_embed.add_field(
            name=f"🏆 {team1_name if winning_team == '강도측' else team2_name} 승리",
            value=f"총 지급액: {format_krw(total_payout)}",
            inline=False
        )
    
    if profit_loss > 0:
        result_embed.add_field(
            name="✅ 업장 순수익",
            value=f"**+{format_krw(profit_loss)}**",
            inline=False
        )
    elif profit_loss < 0:
        result_embed.add_field(
            name="❌ 업장 순손실",
            value=f"**{format_krw(profit_loss)}**",
            inline=False
        )
    else:
        result_embed.add_field(
            name="⚖️ 업장 손익",
            value="**0원 (본전)**",
            inline=False
        )
    
    result_embed.set_footer(text=f"이벤트 유형: {'RP' if event_type == 'rp' else '도주RP' if event_type == 'escape' else '롤'} 배팅")
    
    await ctx.send(embed=result_embed)

async def process_result(ctx, winning_team: str):
    """배팅 결과 처리"""
    bets_data = load_bets()
    
    # 권한 확인: 배팅 시작자 또는 특별 권한 유저만 가능
    if ctx.author.id not in [bets_data.get('starter_id')] + ADMIN_USER_IDS:
        no_permission = discord.Embed(
            title="🚫 권한 없음",
            description="결과 처리는 배팅을 시작한 유저나 관리자만 가능합니다.",
            color=0xff0000
        )
        await ctx.send(embed=no_permission)
        return
        
    # 배팅 데이터가 있는지 확인 (active 상태가 아니어도 처리 가능하도록 변경)
    if not bets_data.get('bets'):
        no_bets_embed = discord.Embed(
            title="ℹ️ 알림",
            description="이번 라운드에 배팅한 유저가 없습니다.",
            color=0x7289da
        )
        await ctx.send(embed=no_bets_embed)
        return
        
    # 채팅 권한 다시 활성화 (보기 권한은 유지)
    voice_channel = ctx.guild.get_channel(bets_data['voice_channel_id'])
    if voice_channel:
        await set_channel_permissions(voice_channel, True)
    
    event_type = bets_data.get('event_type', 'rp')
    
    if event_type == "rp":
        title = f"🎉 **{winning_team} 승리!** 🎉"
        description = "RP 배팅 결과를 확인해주세요."
        team1_name = "강도측"
        team2_name = "보안관 및 경찰측"
        team1_multiplier = ROBBER_WIN_MULTIPLIER
        team2_multiplier = POLICE_WIN_MULTIPLIER
    elif event_type == "lol":
        title = f"🎮 **{'블루팀' if winning_team == '강도측' else '레드팀'} 승리!** 🎮"
        description = "리그 오브 레전드 배팅 결과를 확인해주세요."
        team1_name = "블루팀 (강도측)"
        team2_name = "레드팀 (경찰측)"
        team1_multiplier = LOL_MULTIPLIER
        team2_multiplier = LOL_MULTIPLIER
    elif event_type == "escape":
        title = f"🏃‍♂️ **{'도주측' if winning_team == '강도측' else '추격측'} 승리!** 🏃‍♂️"
        description = "도주RP 배팅 결과를 확인해주세요."
        team1_name = "도주측"
        team2_name = "추격측"
        team1_multiplier = ROBBER_WIN_MULTIPLIER
        team2_multiplier = POLICE_WIN_MULTIPLIER
        
    result_embed = discord.Embed(
        title=title,
        description=description,
        color=0x00ff00,
        timestamp=datetime.now()
    )
    result_embed.set_thumbnail(url="https://i.imgur.com/3Jm8W9x.png")
    
    total_bets = 0
    total_payout = 0
    winner_count = 0
    
    for user_id, bet_info in bets_data['bets'].items():
        member = ctx.guild.get_member(int(user_id))
        if not member:
            continue
            
        amount = bet_info['amount']
        team = bet_info['team']
        total_bets += amount
        
        if team == winning_team:
            multiplier = team1_multiplier if winning_team == "강도측" else team2_multiplier
            payout = int(amount * multiplier)
            result_embed.add_field(
                name=f"✅ {member.display_name}",
                value=f"배팅: {format_krw(amount)}\n지급액: **{format_krw(payout)}** (x{multiplier})",
                inline=False
            )
            total_payout += payout
            winner_count += 1
        else:
            result_embed.add_field(
                name=f"❌ {member.display_name}",
                value=f"배팅: {format_krw(amount)}\n지급액: **지급X**",
                inline=False
            )
    
    result_embed.add_field(
        name="📊 총계",
        value=f"승리한 유저: {winner_count}명\n총 지급 예정 금액: **{format_krw(total_payout)}**",
        inline=False
    )
    
    result_embed.set_footer(text=f"{'블루팀' if winning_team == '강도측' else '레드팀'} 승리로 처리되었습니다" if event_type == "lol" else f"{winning_team} 승리로 처리되었습니다")
    
    if voice_channel:
        await voice_channel.send(embed=result_embed)
    else:
        await ctx.send(embed=result_embed)
    
    # 배팅 데이터 업데이트 (손익 계산을 위해 저장)
    bets_data['winning_team'] = winning_team
    bets_data['total_bets'] = total_bets
    bets_data['total_payout'] = total_payout
    bets_data['active'] = False
    save_bets(bets_data)
    
    # 손익 결과 표시
    await calculate_profit_loss(ctx)
    
    # 배팅 버튼 다시 활성화
    if voice_channel:
        betting_embed = discord.Embed(
            title="🎲 **새 배팅 준비 완료** 🎲",
            description="아래 버튼을 눌러 새로운 배팅을 시작하세요.",
            color=0x7289da,
            timestamp=datetime.now()
        )
        await voice_channel.send(embed=betting_embed, view=BettingButtons())

async def process_bet(ctx, team: str, amount: int):
    """배팅 처리 함수"""
    bets_data = load_bets()
    if not bets_data['active']:
        not_active = discord.Embed(
            title="⚠️ 배팅 진행 중 아님",
            description="현재 배팅이 진행 중이 아닙니다.",
            color=0xffcc00
        )
        await ctx.send(embed=not_active)
        return
        
    if str(ctx.author.id) in bets_data['bets']:
        error_embed = discord.Embed(
            title="❌ 배팅 제한",
            description="이미 배팅에 참여하셨습니다. 한 번만 배팅할 수 있습니다.",
            color=0xff0000
        )
        await ctx.send(embed=error_embed)
        return
        
    user_id = str(ctx.author.id)
    bets_data['bets'][user_id] = {
        'team': team,
        'amount': amount,
        'time': datetime.now().isoformat()
    }
    save_bets(bets_data)
    
    event_type = bets_data.get('event_type', 'rp')
    
    if event_type == "rp":
        team_name = "강도측" if team == "강도측" else "보안관 및 경찰측"
        multiplier = ROBBER_WIN_MULTIPLIER if team == "강도측" else POLICE_WIN_MULTIPLIER
    elif event_type == "lol":
        team_name = "블루팀 (강도측)" if team == "강도측" else "레드팀 (경찰측)"
        multiplier = LOL_MULTIPLIER
    elif event_type == "escape":
        team_name = "도주측" if team == "강도측" else "추격측"
        multiplier = ROBBER_WIN_MULTIPLIER if team == "강도측" else POLICE_WIN_MULTIPLIER
    
    payout = int(amount * multiplier)
    
    success_embed = discord.Embed(
        title="✅ **배팅 접수 완료!**",
        color=0x00ff00,
        timestamp=datetime.now()
    )
    
    success_embed.add_field(name="📌 배팅 팀", value=team_name, inline=True)
    success_embed.add_field(name="💰 배팅 금액", value=format_krw(amount), inline=True)
    success_embed.add_field(name="🎰 예상 지급액", value=f"**{format_krw(payout)}** (x{multiplier})", inline=True)
    success_embed.set_thumbnail(url="https://i.imgur.com/3Jm8W9x.png")
    success_embed.set_footer(text=f"{ctx.author.display_name}님의 배팅이 접수되었습니다")
    
    await ctx.send(embed=success_embed)

async def invalidate_bets(ctx):
    """배팅 무효 처리 명령어"""
    bets_data = load_bets()
    
    # 권한 확인: 배팅 시작자 또는 특별 권한 유저만 가능
    if ctx.author.id not in [bets_data.get('starter_id')] + ADMIN_USER_IDS:
        no_permission = discord.Embed(
            title="🚫 권한 없음",
            description="이 명령어를 사용할 권한이 없습니다.",
            color=0xff0000
        )
        await ctx.send(embed=no_permission)
        return
        
    # 배팅 데이터가 있는지 확인 (active 상태가 아니어도 처리 가능하도록 변경)
    if not bets_data.get('bets'):
        no_bets_embed = discord.Embed(
            title="ℹ️ 알림",
            description="이번 라운드에 배팅한 유저가 없습니다.",
            color=0x7289da
        )
        await ctx.send(embed=no_bets_embed)
        return
        
    # 채팅 권한 다시 활성화 (보기 권한은 유지)
    voice_channel = ctx.guild.get_channel(bets_data['voice_channel_id'])
    if voice_channel:
        await set_channel_permissions(voice_channel, True)
        
    result_embed = discord.Embed(
        title="⚠️ **이벤트 무효 처리** ⚠️",
        description="재알 발생으로 인해 모든 배팅이 패알(업장승리)처리되었습니다.",
        color=0xffcc00,
        timestamp=datetime.now()
    )
    result_embed.set_thumbnail(url="https://i.imgur.com/3Jm8W9x.png")
    
    total_bets = 0
    bet_count = 0
    
    for user_id, bet_info in bets_data['bets'].items():
        member = ctx.guild.get_member(int(user_id))
        if not member:
            continue
            
        amount = bet_info['amount']
        result_embed.add_field(
            name=f"❌ {member.display_name}",
            value=f"배팅: {format_krw(amount)}\n처리: **패알 (지급X)**",
            inline=False
        )
        total_bets += amount
        bet_count += 1
    
    result_embed.add_field(
        name="📊 총계",
        value=f"배팅 참여자: {bet_count}명\n총 배팅 금액: **{format_krw(total_bets)}**\n\n모든 배팅이 재알로 인해 패알 처리되었습니다.",
        inline=False
    )
    
    result_embed.set_footer(text="재알 발생으로 무효(업장승) 처리되었습니다")
    
    if voice_channel:
        await voice_channel.send(embed=result_embed)
    else:
        await ctx.send(embed=result_embed)
    
    # 배팅 데이터 업데이트 (손익 계산을 위해 저장)
    bets_data['winning_team'] = "무효"
    bets_data['total_bets'] = total_bets
    bets_data['total_payout'] = 0  # 무효 처리 시 지급액은 0
    bets_data['active'] = False
    save_bets(bets_data)
    
    # 손익 결과 표시
    await calculate_profit_loss(ctx)
    
    # 배팅 버튼 다시 활성화
    if voice_channel:
        betting_embed = discord.Embed(
            title="🎲 **새 배팅 준비 완료** 🎲",
            description="아래 버튼을 눌러 새로운 배팅을 시작하세요.",
            color=0x7289da,
            timestamp=datetime.now()
        )
        await voice_channel.send(embed=betting_embed, view=BettingButtons())

## ----------------------------
## 음성 채널 시스템 함수
## ----------------------------

async def handle_voice_channel_join(member, after):
    """사용자가 음성 채널에 들어갈 때 처리"""
    if after.channel and after.channel.id == VOICE_CHANNEL_ID:
        category = bot.get_channel(CATEGORY_ID)
        
        # 기존에 같은 이름의 채널이 있는지 확인
        existing_channel = discord.utils.get(category.voice_channels, name=f"{VOICE_CHANNEL_PREFIX}{member.display_name}")
        
        if not existing_channel:
            # 카테고리 내 마지막 위치에 채널 생성
            position = len(category.voice_channels)
            
            new_channel = await category.create_voice_channel(
                name=f"{VOICE_CHANNEL_PREFIX}{member.display_name}",
                position=position
            )
            
            # 사용자를 새 채널로 이동
            try:
                await member.move_to(new_channel)
                
                # 새 채널에 배팅 안내 메시지 전송
                embed = discord.Embed(
                    title="🎤 음성 채널이 생성되었습니다",
                    description=f"이 채널에서 배팅을 시작할 수 있습니다.\n관리자는 아래 버튼을 눌러 배팅을 시작하세요.",
                    color=0x7289da
                )
                await new_channel.send(embed=embed, view=BettingButtons())
                
            except discord.HTTPException:
                pass

async def handle_voice_channel_leave(member, before):
    """사용자가 음성 채널을 나갈 때 처리 (빈 채널 삭제)"""
    if before.channel and before.channel.category_id == CATEGORY_ID and before.channel.id != VOICE_CHANNEL_ID:
        if len(before.channel.members) == 0:
            try:
                await before.channel.delete()
            except discord.HTTPException:
                pass

## ----------------------------
## 이벤트 핸들러
## ----------------------------

@bot.event
async def on_ready():
    """봇 준비 완료 시 실행"""
    print(f'{bot.user.name}으로 로그인 성공!')
    await bot.change_presence(activity=discord.Game(name="음성 채널 배팅 시스템"))
    init_bets_file()
    
    # 버튼 뷰 등록
    bot.add_view(BettingButtons())
    bot.add_view(ResultButtons())

@bot.event
async def on_voice_state_update(member, before, after):
    """음성 상태 변경 시 처리"""
    await handle_voice_channel_join(member, after)
    await handle_voice_channel_leave(member, before)

## ----------------------------
## 배팅 시스템 명령어
## ----------------------------

@bot.command(name='익명')
async def anonymous_start(ctx, event_type: str = None):
    """익명 이벤트 시작 명령어 (버튼 방식으로 대체)"""
    # 쿨다운 확인
    current_time = datetime.now().timestamp()
    last_used = cooldowns.get(ctx.author.id, 0)
    
    if current_time - last_used < COOLDOWN_TIME:
        remaining = int(COOLDOWN_TIME - (current_time - last_used))
        await ctx.send(f"🚫 쿨다운 중입니다. {remaining}초 후에 다시 시도해주세요.")
        return
    
    if ctx.author.id not in ADMIN_USER_IDS:
        no_permission = discord.Embed(
            title="🚫 권한 없음",
            description="이 명령어를 사용할 권한이 없습니다.",
            color=0xff0000
        )
        await ctx.send(embed=no_permission)
        return
    
    # 사용자가 음성 채널에 있는지 확인
    if not ctx.author.voice or not ctx.author.voice.channel:
        no_voice = discord.Embed(
            title="❌ 오류",
            description="음성 채널에 접속한 상태에서만 사용할 수 있습니다.",
            color=0xff0000
        )
        await ctx.send(embed=no_voice)
        return
    
    voice_channel = ctx.author.voice.channel
    
    # 쿨다운 적용
    cooldowns[ctx.author.id] = current_time
    
    if not event_type:
        help_embed = discord.Embed(
            title="ℹ️ 사용법 안내",
            description="`!익명 [이벤트타입]`\n\n이벤트 타입:\n- `도주`: 도주RP 이벤트 시작\n- `롤`: 리그 오브 레전드 배팅 시작\n(기본값: RP 이벤트)\n\n또는 아래 버튼을 사용하세요.",
            color=0x7289da
        )
        await ctx.send(embed=help_embed, view=BettingButtons())
        return
    
    event_type = event_type.lower()
    
    if event_type == "도주":
        starting_embed = discord.Embed(
            title="🏃‍♂️ **익명 도주RP 이벤트 시작**",
            description=f"관리자에 의해 익명 도주RP 이벤트가 시작되었습니다! (최소 {format_krw(MIN_BET_AMOUNT)} ~ 최대 {format_krw(MAX_BET_AMOUNT)})\n\n⚠️ RP 중 재알 발생 시 모든 배팅은 패알(업장승리) 처리됩니다.",
            color=0x7289da,
            timestamp=datetime.now()
        )
        starting_embed.set_footer(text=f"시작한 관리자: {ctx.author.display_name}")
        await voice_channel.send(embed=starting_embed)
        await start_betting(ctx, "escape", voice_channel)
        
    elif event_type == "롤":
        starting_embed = discord.Embed(
            title="🎮 **리그 오브 레전드 배팅 시작**",
            description=f"관리자에 의해 리그 오브 레전드 배팅이 시작되었습니다! (최소 {format_krw(MIN_BET_AMOUNT)} ~ 최대 {format_krw(MAX_BET_AMOUNT)})\n\n양측 배당률: 1.95배",
            color=0x7289da,
            timestamp=datetime.now()
        )
        starting_embed.add_field(
            name="🔵 블루팀 (강도측)",
            value="`!강도 [금액]` 명령어로 배팅",
            inline=True
        )
        starting_embed.add_field(
            name="🔴 레드팀 (경찰측)",
            value="`!경찰 [금액]` 명령어로 배팅",
            inline=True
        )
        starting_embed.set_footer(text=f"시작한 관리자: {ctx.author.display_name}")
        await voice_channel.send(embed=starting_embed)
        await start_betting(ctx, "lol", voice_channel)
        
    else:
        starting_embed = discord.Embed(
            title="🕶️ **익명 RP 이벤트 시작**",
            description=f"관리자에 의해 익명 RP 이벤트가 시작되었습니다! (최소 {format_krw(MIN_BET_AMOUNT)} ~ 최대 {format_krw(MAX_BET_AMOUNT)})\n\n⚠️ RP 중 재알 발생 시 모든 배팅은 패알(업장승리) 처리됩니다.",
            color=0x7289da,
            timestamp=datetime.now()
        )
        starting_embed.set_footer(text=f"시작한 관리자: {ctx.author.display_name}")
        await voice_channel.send(embed=starting_embed)
        await start_betting(ctx, "rp", voice_channel)

@bot.group(name='강도', invoke_without_command=True)
async def robber(ctx, *, amount_text: str = None):
    """강도측 배팅 명령어"""
    if ctx.invoked_subcommand is None:
        if amount_text:
            try:
                amount = korean_to_number(amount_text)
                await process_bet(ctx, "강도측", amount)
            except ValueError as e:
                error_embed = discord.Embed(
                    title="❌ 금액 오류",
                    description=str(e),
                    color=0xff0000
                )
                await ctx.send(embed=error_embed)
            except:
                help_embed = discord.Embed(
                    title="ℹ️ 사용법 안내",
                    description=f"`!강도 [금액]` (배팅)\n최소 {format_krw(MIN_BET_AMOUNT)} ~ 최대 {format_krw(MAX_BET_AMOUNT)}\n예: `!강도 1억`, `!강도 3억7천500만`",
                    color=0x7289da
                )
                await ctx.send(embed=help_embed)
        else:
            help_embed = discord.Embed(
                title="ℹ️ 사용법 안내",
                description=f"`!강도 [금액]` (배팅)\n최소 {format_krw(MIN_BET_AMOUNT)} ~ 최대 {format_krw(MAX_BET_AMOUNT)}\n예: `!강도 1억`, `!강도 3억7천500만`",
                color=0x7289da
            )
            await ctx.send(embed=help_embed)

@robber.command(name='승리')
async def robber_win(ctx):
    """강도측 승리 처리"""
    await process_result(ctx, "강도측")

@bot.group(name='경찰', invoke_without_command=True)
async def police(ctx, *, amount_text: str = None):
    """경찰측 배팅 명령어"""
    if ctx.invoked_subcommand is None:
        if amount_text:
            try:
                amount = korean_to_number(amount_text)
                await process_bet(ctx, "보안관 및 경찰측", amount)
            except ValueError as e:
                error_embed = discord.Embed(
                    title="❌ 금액 오류",
                    description=str(e),
                    color=0xff0000
                )
                await ctx.send(embed=error_embed)
            except:
                help_embed = discord.Embed(
                    title="ℹ️ 사용법 안내",
                    description=f"`!경찰 [금액]` (배팅)\n최소 {format_krw(MIN_BET_AMOUNT)} ~ 최대 {format_krw(MAX_BET_AMOUNT)}\n예: `!경찰 1억`, `!경찰 12억3천450만`",
                    color=0x7289da
                )
                await ctx.send(embed=help_embed)
        else:
            help_embed = discord.Embed(
                title="ℹ️ 사용법 안내",
                description=f"`!경찰 [금액]` (배팅)\n최소 {format_krw(MIN_BET_AMOUNT)} ~ 최대 {format_krw(MAX_BET_AMOUNT)}\n예: `!경찰 1억`, `!경찰 12억3천450만`",
                color=0x7289da
            )
            await ctx.send(embed=help_embed)

@police.command(name='승리')
async def police_win(ctx):
    """경찰측 승리 처리"""
    await process_result(ctx, "보안관 및 경찰측")

@bot.command(name='무효')
async def invalidate_bets_command(ctx):
    """배팅 무효 처리 명령어"""
    await invalidate_bets(ctx)

@bot.command(name='현재배팅')
async def current_bets(ctx):
    """현재 배팅 현황 확인"""
    bets_data = load_bets()
    
    if not bets_data['bets']:
        no_bets_embed = discord.Embed(
            title="ℹ️ 현재 배팅 현황",
            description="현재 배팅이 없습니다.",
            color=0x7289da
        )
        await ctx.send(embed=no_bets_embed)
        return
        
    robber_bets = []
    police_bets = []
    total_robber = 0
    total_police = 0
    
    event_type = bets_data.get('event_type', 'rp')
    
    for user_id, bet_info in bets_data['bets'].items():
        member = ctx.guild.get_member(int(user_id))
        if not member:
            continue
            
        if bet_info['team'] == "강도측":
            robber_bets.append(f"• {member.display_name}: {format_krw(bet_info['amount'])}")
            total_robber += bet_info['amount']
        else:
            police_bets.append(f"• {member.display_name}: {format_krw(bet_info['amount'])}")
            total_police += bet_info['amount']
    
    if event_type == "rp":
        team1_name = "🔫 강도측"
        team2_name = "👮 보안관 및 경찰측"
    elif event_type == "lol":
        team1_name = "🔵 블루팀 (강도측)"
        team2_name = "🔴 레드팀 (경찰측)"
    elif event_type == "escape":
        team1_name = "🏃‍♂️ 도주측"
        team2_name = "👮 추격측"
    
    status_embed = discord.Embed(
        title="📊 **현재 배팅 현황**",
        color=0x7289da,
        timestamp=datetime.now()
    )
    
    if robber_bets:
        status_embed.add_field(
            name=f"{team1_name} 배팅 (총 {format_krw(total_robber)})",
            value="\n".join(robber_bets) or "없음",
            inline=False
        )
    
    if police_bets:
        status_embed.add_field(
            name=f"{team2_name} 배팅 (총 {format_krw(total_police)})",
            value="\n".join(police_bets) or "없음",
            inline=False
        )
    
    if bets_data['active']:
        start_time = datetime.fromisoformat(bets_data['start_time'])
        end_time = start_time + timedelta(seconds=BETTING_OPEN_DURATION)
        remaining = end_time - datetime.now()
        
        if remaining.total_seconds() > 0:
            status_embed.set_footer(text=f"배팅 마감까지 {int(remaining.total_seconds())}초 남음")
        else:
            status_embed.set_footer(text="배팅이 곧 마감됩니다")
    else:
        status_embed.set_footer(text="배팅이 마감되었습니다")
    
    status_embed.set_thumbnail(url="https://i.imgur.com/3Jm8W9x.png")
    await ctx.send(embed=status_embed)

@bot.command(name='손익')
async def profit_loss(ctx):
    """업장 손익 확인 명령어"""
    await calculate_profit_loss(ctx)

## ----------------------------
## 봇 실행
## ----------------------------

if __name__ == "__main__":
    bot.run('MTM4NjU1MTYwNTg1MTMyODU3Mg.GxiiT5.WDyRvQTXpltgrbUOy2YmTGOw9dCeiXc1GuqOGM')
