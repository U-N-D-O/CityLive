enum TransportMode {
  drive('Drive', 'Fastest route by car'),
  bus('Bus', 'Show stops, lines, and departure options'),
  walk('Walk', 'Pedestrian route'),
  taxi('Taxi', 'Taxi companies and pickup options'),
  bike('Bike', 'Bike-friendly route');

  const TransportMode(this.label, this.description);

  final String label;
  final String description;
}
