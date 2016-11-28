# Description:
#   D&D related commands.
#
# Commands:
#   hubot attr [@<username>] maxhp <amount> - Set your character's maximum HP
#   hubot attr [@<username>] dex <score> - Set your character's dexterity score
#   hubot hp <amount> - Set your character's HP to a fixed amount
#   hubot hp +/-<amount> - Add or remove HP from your character
#   hubot initiative clear - Reset all initiative counts. (DM only)
#   hubot initiative [@<username] <score> - Set your character's initiative count
#   hubot initiative next - Advance the initiative count and announce the next character
#   hubot initiative report - Show all initiative counts.
#   hubot character sheet [@<username>] - Summarize current character statistics
#   hubot character report - Summarize all character statistics

DM_ROLE = 'dungeon master'

INITIATIVE_MAP_DEFAULT =
  scores: []
  current: null

ATTRIBUTES = ['maxhp', 'str', 'dex', 'con', 'int', 'wis', 'cha']

module.exports = (robot) ->

  dmOnly = (msg) ->
    if robot.auth.hasRole(msg.message.user, DM_ROLE)
      true
    else
      msg.reply [
        "You can't do that! You're not a *#{DM_ROLE}*."
        "Ask an admin to run `#{robot.name} grant #{msg.message.user.name} the #{DM_ROLE} role`."
      ].join("\n")
      false

  characterNameFrom = (msg) ->
    if msg.match[1]?
      # Explicit username. DM-only
      return null unless dmOnly(msg) or msg.match[1] is msg.message.user.name
      msg.match[1]
    else
      msg.message.user.name

  withCharacter = (msg, callback) ->
    username = characterNameFrom msg
    return unless username?

    existing = true
    characterMap = robot.brain.get('dnd:characterMap') or {}
    character = characterMap[username]
    unless character?
      existing = false
      character = {
        username: username
      }

    callback(existing, character)
    characterMap[username] = character

    robot.brain.set('dnd:characterMap', characterMap)

  robot.respond /attr\s+(?:@?(\w+)\s+)?(\w+)\s+(\d+)/i, (msg) ->
    attrName = msg.match[1]
    score = parseInt(msg.match[2])

    unless ATTRIBUTES.indexOf(attrName) isnt -1
      msg.reply [
        "#{attrName} isn't a valid attribute name."
        "Known attributes include: #{ATTRIBUTES.join ' '}"
      ].join "\n"
      return

    withCharacter msg, (existing, character) ->
      character[attrName] = score

  robot.respond /maxhp\s+(?:@?(\w+)\s+)?(\d+)/i, (msg) ->
    amount = parseInt(msg.match[2])

    withCharacter msg, (existing, character) ->
      character.maxHP = amount
      if character.currentHP and character.currentHP > character.maxHP
        character.currentHP = character.maxHP
      msg.reply "@#{character.username}'s maximum HP is now #{amount}."

  robot.respond /hp\s+(?:@?(\w+)\s+)?(\+|-)?\s*(\d+)/i, (msg) ->
    op = msg.match[2] or '='
    amount = parseInt(msg.match[3])

    withCharacter msg, (existing, character) ->
      unless character.maxHP?
        msg.reply [
          "@#{character.username}'s maximum HP isn't set."
          "Please run `@#{robot.name}: attr maxhp <amount>` first."
        ].join("\n")
        return

      initHP = character.currentHP or character.maxHP

      finalHP = switch op
        when '+' then initHP + amount
        when '-' then initHP - amount
        else amount

      finalHP = character.maxHP if finalHP > character.maxHP
      character.currentHP = finalHP

      lines = ["@#{character.username}'s HP: #{initHP} :point_right: #{finalHP} / #{character.maxHP}"]
      if finalHP <= 0
        lines.push "@#{character.username} is KO'ed!"
      msg.send lines.join("\n")

  robot.respond /initiative\s+clear/i, (msg) ->
    robot.brain.set 'dnd:initiativeMap', INITIATIVE_MAP_DEFAULT
    msg.reply 'All initiative counts cleared.'

  robot.respond /initiative(?:\s+@?(\w+))?\s+(-?\d+)/, (msg) ->
    score = parseInt(msg.match[2])

    initiativeMap = robot.brain.get('dnd:initiativeMap') or INITIATIVE_MAP_DEFAULT
    withCharacter msg, (existing, character) ->
      existing = null
      for each in initiativeMap.scores
        existing = each if each.username is character.username

      if existing?
        existing.score = score
      else
        created =
          username: character.username
          score: score
        initiativeMap.scores.push created

      # Sort score array in decreasing initiative score.
      initiativeMap.scores.sort (a, b) -> a.score - b.score

      msg.send "@#{character.username} will go at initiative count #{score}."

  robot.respond /initiative\s+next/i, (msg) ->
    initiativeMap = robot.brain.get('dnd:initiativeMap') or INITIATIVE_MAP_DEFAULT

    unless initiativeMap.scores.length > 0
      msg.reply 'No known initiative scores.'
      return

    if initiativeMap.current?
      nextCount = initiativeMap.current + 1
      nextCount = 0 if nextCount >= initiativeMap.scores.length
    else
      nextCount = 0

    current = initiativeMap.scores[nextCount]
    initiativeMap.current = nextCount
    msg.send "@#{current.username} is up. _(#{current.score})_"

  robot.respond /initiative\s+report/i, (msg) ->
    initiativeMap = robot.brain.get('dnd:initiativeMap') or INITIATIVE_MAP_DEFAULT

    unless initiativeMap.scores.length > 0
      msg.reply 'No known initiative scores.'
      return

    lines = []
    i = 0
    for each in initiativeMap.scores
      prefix = ''
      prefix = ':arrow_right: ' if (initiativeMap.current or 0) is i
      lines.push "#{prefix}_(#{each.score})_ @#{each.username}"
      i++

    msg.send lines.join "\n"

  robot.respond /character sheet(?:\s+@?(\w+))?/i, (msg) ->
    withCharacter msg, (existing, character) ->
      unless existing
        msg.reply "No character data for #{character.username} yet."
        return

      msg.send "*HP:* #{character.currentHP} / #{character.maxHP}"

  robot.respond /character report/i, (msg) ->
    characterMap = robot.brain.get('dnd:characterMap') or {}
    lines = []
    for username, character of characterMap
      lines.push "*#{username}*: HP #{character.currentHP}/#{character.maxHP}"
    msg.send lines.join "\n"
