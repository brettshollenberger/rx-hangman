require_relative "../middlewares/frp/socket_http"

class GuessesController
  class << self
    include SocketHTTP
  end

  def self.index(body)
    room = Hangman::BookKeeper.rooms.send(body.room_name)

    socket_response :get, "/guesses/:room_name", {
      room: {
        name: body.room_name
      },
      guesses: room.game.guesses
    }
  end

  def self.create(body)
    room    = Hangman::BookKeeper.rooms.send(body.roomName)
    game    = room.game
    guesser = body.guesser
    guess   = body.guess

    begin
      result = game.guess(guesser, guess)
      notify_guessed(room, guesser, guess)
      notify_word(room)
      notify_guesses(room)
      notify_hangman(room)
      notify_game_over(room)
    rescue => e
      notify_error(e, guesser, guess, room)
    end

    socket_response :post, "/guesses/:room_name", {}
  end

private
  def self.notify_guessed(room, guesser, guess)
    room.each do |player|
      player.socket.send controller_action NotificationsController, "show", {
        room_name: room.name,
        game: room.game,
        player: player.name,
        notification: :letter_guessed,
        guesser: guesser,
        guess: guess
      }
    end
  end

  def self.notify_word(room)
    each_connection(room) do |sock|
      sock.send controller_action WordsController, "show", {room_name: room.name}
    end
  end

  def self.notify_guesses(room)
    each_connection(room) do |sock|
      sock.send controller_action GuessesController, "index", {room_name: room.name}
    end
  end

  def self.notify_hangman(room)
    each_connection(room) do |sock|
      sock.send controller_action HangmanController, "show", {room_name: room.name}
    end
  end

  def self.notify_game_over(room)
    if room.game.won?
      room.each do |player|
        player.socket.send controller_action NotificationsController, "show", {
          room_name: room.name,
          game: room.game,
          player: player.name,
          notification: :won
        }
      end
    end

    if room.game.lost?
      each_connection(room) do |sock|
        sock.send controller_action NotificationsController, "show", {
          room_name: room.name,
          game: room.game,
          notification: :lost
        }
      end
    end
  end

  def self.notify_error(error, guesser, guess, room)
    room.select { |player| player.name == guesser }.each do |player|
      player.socket.send controller_action NotificationsController, "show", {
        room_name: room.name,
        game: room.game,
        player: player.name,
        notification: :error,
        error: error,
        guesser: guesser,
        guess: guess
      }
    end
  end
end
