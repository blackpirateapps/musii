enum YouTubeMusicCategory {
  songs('Songs'),
  albums('Albums'),
  artists('Artists'),
  playlists('Playlists');

  const YouTubeMusicCategory(this.label);
  final String label;
}

typedef YouTubeMusicCollection = ({
  String browseId,
  YouTubeMusicCategory category,
  String title,
  String? subtitle,
  String? artworkUrl,
});
