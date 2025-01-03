import 'dart:core';
import 'package:prompt_chat/cli/category.dart';
import 'package:prompt_chat/cli/channel.dart';
import 'package:prompt_chat/cli/exceptions/weak_pass.dart';
import 'package:prompt_chat/cli/message.dart';
import 'package:prompt_chat/cli/user.dart';
import 'package:prompt_chat/cli/server.dart';
import 'package:prompt_chat/cli/role.dart';
import 'package:prompt_chat/cli/exceptions/invalid_creds.dart';
import 'package:prompt_chat/db/database_crud.dart';
import 'package:prompt_chat/enum/channel_type.dart';
import 'package:prompt_chat/enum/permissions.dart';
import 'package:prompt_chat/enum/server_type.dart';

class ChatAPI {
  List<User> users = [];
  List<Server> servers = [];
  bool someoneLoggedIn = false;

  // Populate users & servers array from db
  Future<void> populateArrays() async {
    // users.forEach((element) {print(element.username);});
    users = await UserIO.getAllUsers();
    servers = await ServerIO.getAllServers();
  }

  // Check if a given username exists
  Future<bool> isUsernameExists(String username) async {
    var usernames = users.map((e) => e.username).toList();
    return usernames.contains(username);
  }

  // Register a user
  Future<void> registerUser(String? username, String? password) async {
    if (username == null || password == null) {
      throw InvalidCredentialsException();
    }
    if (await isUsernameExists(username)) {
      throw Exception("User already exists");
    }
    var newUser = User(username, password, false);

    users.add(newUser);
    await newUser.register();
  }

  // Display all the messages in a given server
  void displayMessages(String? serverName) {
    if (serverName == null) {
      throw Exception("Please enter a valid command");
    }
    var reqServer = getServer(serverName);
    for (Channel channel in reqServer.channels) {
      print("${channel.channelName} : ");
      for (Message message in channel.messages) {
        print("${message.sender.username} : ${message.content}");
      }
    }
  }

  // Display all the servers, categories and channels associated with the user.
  void displayUserServers() {
    // Create indentation using '\t' repeated 'level' times
    void printIndented(String text, int level) {
      print('${'\t' * level}- $text');
    }

    var username = getCurrentLoggedIn();
    if (username == null) throw Exception("You must be logged in!");
    List<Server> userServers =
        servers.where((element) => element.isMember(username)).toList();

    for (var server in userServers) {
      print(server.serverName);

      for (var category in server.categories) {
        printIndented("Category: ${category.categoryName}", 1);

        List<Channel> channels = [];
        if (server.isAccessAllowed(username, 2)) {
          channels = category.channels;
        } else if (server.isAccessAllowed(username, 1)) {
          channels = category.channels
              .where((element) => element.permission != Permission.owner)
              .toList();
        }

        for (var channel in channels) {
          printIndented("Channel: ${channel.channelName}", 2);
        }
      }
    }
  }

  // Login a user
  Future<void> loginUser(String? username, String? password) async {
    if (password == null || username == null) {
      throw InvalidCredentialsException();
    }
    if (!isPasswordValid(password)) {
      throw WeakPasswordException();
    }
    if (someoneLoggedIn) {
      throw Exception("Please logout of the current session to login again");
    }
    var reqUser = getUser(username);
    await reqUser.login(password);
    someoneLoggedIn = true;
  }

  // Checks if the password is atleast 8 characters long, having atleast a number & a special character
  bool isPasswordValid(String password) {
    if (password.length < 8) {
      return false;
    }
    bool hasNum = password.contains(RegExp(r'[0-9]'));
    bool hasChar = password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));
    return hasNum && hasChar;
  }

  // Logout a user
  Future<void> logoutUser(String? username) async {
    if (username == null) {
      throw InvalidCredentialsException();
    }
    var reqUser = getUser(username);
    reqUser.loggedIn = false;
    someoneLoggedIn = false;
    await reqUser.logout();
  }

  // Get user object from username
  User getUser(String name) {
    return users.firstWhere((user) => user.username == name,
        orElse: () => throw Exception("User does not exist"));
  }

  // Get username of current logged in user
  String? getCurrentLoggedIn() {
    for (User user in users) {
      if (user.loggedIn) {
        return user.username;
      }
    }
    return null;
  }

  // Display the list of all users
  void displayUsers() {
    for (User user in users) {
      print(user.username);
    }
  }

  // Create a new server with given config
  Future<void> createServer(
      String? serverName, String? userName, String? serverPerm) async {
    if (serverName == null || userName == null) {
      throw Exception(
          "Please enter the required credentials, or login to continue.");
    }
    JoinPerm joinPerm = getJoinPerm(serverPerm);
    var creator = getUser(userName);
    var newServer = createNewServer(serverName, joinPerm);
    servers.add(newServer);
    await newServer.instantiateServer(creator);
  }

  // Get JoinPerm object
  JoinPerm getJoinPerm(String? serverPerm) {
    if (serverPerm == "closed") {
      return JoinPerm.closed;
    }
    return JoinPerm.open;
  }

  // Creates a new server with given name and join permission
  Server createNewServer(String serverName, JoinPerm perm) {
    return Server(
      serverName: serverName,
      members: [],
      roles: [],
      categories: [Category(categoryName: "none", channels: [])],
      channels: [],
      joinPerm: perm,
    );
  }

  // Get Server object by server name
  Server getServer(String name) {
    return servers.firstWhere((server) => server.serverName == name,
        orElse: () => throw Exception("Server does not exist"));
  }

  // Add member to server if they have requried access level
  Future<void> addMemberToServer(
      String? serverName, String? userName, String? ownerName) async {
    if (serverName == null || userName == null || ownerName == null) {
      throw Exception(
          "Please enter the correct command, or login to continue.");
    }
    var reqUser = getUser(userName);
    var reqServer = getServer(serverName);
    reqServer.checkAccessLevel(ownerName, 2);
    await reqServer.addMember(reqUser);
  }

  // Allows mods & owner to remove member from server.
  Future<void> kickoutFromServer(
      String? serverName, String? userName, String? callerName) async {
    if (serverName == null || userName == null || callerName == null) {
      throw Exception(
          "Please enter the correct command, or login to continue.");
    }
    var reqServer = getServer(serverName);

    if (reqServer.getRole("owner").holders[0].username == userName) {
      throw Exception("The owner cannot be kicked out of the server.");
    }

    // check if the caller is owner
    if (reqServer.getRole("owner").holders[0].username == callerName) {
      leaveServer(serverName, userName);
    } else {
      // confirm that the caller is moderator
      reqServer.checkAccessLevel(callerName, 1);

      // check if the user being kicked out is not another moderator
      if (reqServer.isAccessAllowed(userName, 1)) {
        throw Exception("A moderator cannot kick out another moderator.");
      }
      leaveServer(serverName, userName);
    }
  }

  // Add a category to server
  Future<void> addCategoryToServer(
      String? serverName, String? categoryName, String? userName) async {
    if (serverName == null || categoryName == null || userName == null) {
      throw Exception(
          "Please enter the valid credentials, or login to continue.");
    }
    var reqServer = getServer(serverName);
    reqServer.checkAccessLevel(userName, 2);
    await reqServer
        .addCategory(Category(categoryName: categoryName, channels: []));
  }

  // Add a channel to server
  Future<void> addChannelToServer(
      String? serverName,
      String? channelName,
      String? channelPerm,
      String? channelType,
      String? parentCategoryName,
      String? userName) async {
    if (serverName == null ||
        channelName == null ||
        channelPerm == null ||
        channelType == null ||
        userName == null) {
      throw Exception(
          "Please enter the valid credentials, or login to continue.");
    }
    parentCategoryName ??= "none";

    var chanType = getChannelType(channelType);
    var perm = getPermission(channelPerm);
    var reqServer = getServer(serverName);
    reqServer.checkAccessLevel(userName, 2);
    await reqServer.addChannel(
        Channel(
            channelName: channelName,
            messages: [],
            type: chanType,
            permission: perm),
        parentCategoryName);
  }

  // Get the ChannelType object from string
  ChannelType getChannelType(String channelType) {
    switch (channelType) {
      case "video":
        return ChannelType.video;
      case "voice":
        return ChannelType.voice;
      default:
        return ChannelType.text;
    }
  }

  // Get the Permission object from string
  Permission getPermission(String channelPerm) {
    switch (channelPerm) {
      case "owner":
        return Permission.owner;
      case "moderator":
        return Permission.moderator;
      default:
        return Permission.member;
    }
  }

  // Send message in a server
  Future<void> sendMessageInServer(String? serverName, String? userName,
      String? channelName, String? messageContent) async {
    if (serverName == null ||
        userName == null ||
        channelName == null ||
        messageContent == null) {
      throw Exception("Please enter a valid command, or login to continue.");
    }
    var reqServer = getServer(serverName);
    var reqUser = getUser(userName);
    var reqChannel = reqServer.getChannel(channelName);
    if (reqChannel.type != ChannelType.text) {
      throw Exception("You can only send a message in a text channel");
    }
    if (!(reqUser.loggedIn)) {
      throw Exception("Not logged in");
    }
    await reqServer.addMessageToChannel(
        reqChannel, reqUser, Message(messageContent, reqUser));
  }

  // Create a new role in server with given permision
  Future<void> createRole(String? serverName, String? roleName,
      String? permLevel, String? callerName) async {
    if (serverName == null ||
        roleName == null ||
        permLevel == null ||
        callerName == null) {
      throw Exception("Invalid command");
    }

    var newPerm = getRolePermission(permLevel);
    var reqServer = getServer(serverName);
    reqServer.checkAccessLevel(callerName, 2);
    await reqServer
        .addRole(Role(roleName: roleName, accessLevel: newPerm, holders: []));
  }

  // Get the role Permission from string
  Permission getRolePermission(String? permLevel) {
    if (permLevel == "owner") {
      throw Exception("Owner privileges cannot be shared to other roles.");
    } else if (permLevel == "moderator") {
      return Permission.moderator;
    } else {
      return Permission.member;
    }
  }

  // Assign role to user in the server
  Future<void> addRoleToUser(String? serverName, String? roleName,
      String? memberName, String? callerName) async {
    if (serverName == null ||
        roleName == null ||
        memberName == null ||
        callerName == null) {
      throw Exception("Enter a valid command");
    }
    var reqServer = getServer(serverName);
    reqServer.checkAccessLevel(callerName, 2);
    if (!(reqServer.isMember(memberName))) {
      throw Exception("User is not a member of the server");
    }
    if (roleName == "owner") {
      throw Exception("There can only be one owner");
    }
    var reqRole = reqServer.getRole(roleName);
    var reqMember = reqServer.getMember(memberName);
    await reqServer.assignRole(reqRole, reqMember);
  }

  // Add channel to given category in the server
  Future<void> addChannelToCategory(String? serverName, String? channelName,
      String? categoryName, String? callerName) async {
    if (serverName == null ||
        channelName == null ||
        categoryName == null ||
        callerName == null) {
      throw Exception("Please enter a valid command, or login to continue");
    }
    var reqServer = getServer(serverName);
    reqServer.checkAccessLevel(callerName, 2);
    await reqServer.assignChannel(channelName, categoryName);
  }

  // Change permission level of channel in the server
  Future<void> changePermission(String? serverName, String? channelName,
      String? newPerm, String? callerName) async {
    if (serverName == null ||
        channelName == null ||
        newPerm == null ||
        callerName == null) {
      throw Exception("Please enter a valid command, or login to continue");
    }
    var perm = getPermission(newPerm);
    var reqServer = getServer(serverName);
    reqServer.checkAccessLevel(callerName, 2);
    await reqServer.changePerm(channelName, perm);
  }

  // Change ownership of the server
  Future<void> changeOwnership(
      String? serverName, String? currentOwner, String? newOwner) async {
    if (currentOwner == null || newOwner == null || serverName == null) {
      throw Exception("Please enter a valid command, or login to continue");
    }
    var reqServer = getServer(serverName);
    getUser(currentOwner);
    getUser(newOwner);
    reqServer.checkAccessLevel(currentOwner, 2);
    if (!(reqServer.isMember(newOwner))) {
      throw Exception("The specified user is not a member of the server");
    }
    await reqServer.swapOwner(currentOwner, newOwner);
  }

  // Allow user to join server
  Future<void> joinServer(String? serverName, String? joinerName) async {
    if (serverName == null || joinerName == null) {
      throw Exception("Please enter a valid command, or login to continue");
    }
    var reqUser = getUser(joinerName);
    var reqServer = getServer(serverName);
    if (reqServer.isMember(reqUser.username)) {
      throw Exception("The user is already a member of the server");
    }
    if (reqServer.joinPerm == JoinPerm.closed) {
      throw Exception(
          "The server is not open to join, ask to be added to the server by the owner");
    }
    await reqServer.addMember(reqUser);
  }

  // Allow user to leave the server
  Future<void> leaveServer(String? serverName, String? callerName) async {
    if (serverName == null || callerName == null) {
      throw Exception("Please enter a valid command, or login to continue");
    }
    var reqServer = getServer(serverName);
    getUser(callerName);
    if (!(reqServer.isMember(callerName))) {
      throw Exception("The user is not a member of the server");
    }
    //if user leaving is owner
    if (reqServer.getRole("owner").holders[0].username == callerName) {
      throw Exception(
          "Please change ownership before leaving your server, as you are the owner");
    }
    await reqServer.removeMember(callerName);
  }

  // Display all the channels in every category in every server
  void displayChannels() {
    for (Server server in servers) {
      for (Category category in server.categories) {
        print(category.categoryName);
        for (Channel channel in category.channels) {
          print(channel.channelName);
        }
      }
    }
  }
}
