const fs = require('fs');
const path = require('path');
const parseOSM = require('osm-pbf-parser');
const through = require('through2');

const workspaceRoot = path.resolve(__dirname, '..', '..');
const pbfPath = process.argv[2]
  ? path.resolve(process.argv[2])
  : path.join(workspaceRoot, 'greenland-260810.osm.pbf');
const outputDir = path.join(workspaceRoot, 'assets', 'data');

const bounds = {
  west: -51.86,
  south: 64.10,
  east: -51.57,
  north: 64.25,
};

const drivableHighways = new Set([
  'motorway',
  'trunk',
  'primary',
  'secondary',
  'tertiary',
  'unclassified',
  'residential',
  'living_street',
  'service',
  'road',
]);

const nodeCoordinates = new Map();
const searchEntries = new Map();
const routeNodes = new Map();
const routeEdges = new Map();
const streetNames = new Set();

if (!fs.existsSync(pbfPath)) {
  throw new Error(`PBF file not found: ${pbfPath}`);
}

function inNuuk(lat, lon) {
  return (
    lat >= bounds.south &&
    lat <= bounds.north &&
    lon >= bounds.west &&
    lon <= bounds.east
  );
}

function normalize(value) {
  return String(value || '')
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9æøå]+/g, ' ')
    .trim();
}

function brandText(tags) {
  return normalize(
    [
      tags.name,
      tags.brand,
      tags.operator,
      tags['name:kl'],
      tags['name:da'],
      tags['name:en'],
    ]
      .filter(Boolean)
      .join(' ')
  );
}

function isKnownGroceryBrand(tags) {
  const text = brandText(tags);
  return /\b(brugseni|pisiffik|akiki|nukøb|nukoeb|nukob)\b/.test(text);
}

function placeClassification(tags) {
  const shop = tags.shop;
  const amenity = tags.amenity;
  const tourism = tags.tourism;
  const leisure = tags.leisure;

  if (isKnownGroceryBrand(tags) || shop === 'supermarket' || shop === 'grocery') {
    return {
      group: 'Grocery',
      subcategory: 'Grocery store',
      icon: 'grocery',
    };
  }

  if (shop === 'convenience') {
    return {
      group: 'Grocery',
      subcategory: 'Convenience store',
      icon: 'convenience',
    };
  }

  if (['restaurant', 'cafe', 'fast_food', 'bar'].includes(amenity)) {
    return {
      group: 'Food & Drink',
      subcategory: titleCase(amenity),
      icon: amenity === 'cafe' ? 'cafe' : 'restaurant',
    };
  }

  if (tourism || ['park', 'playground', 'sports_centre'].includes(leisure)) {
    return {
      group: 'Attractions',
      subcategory: titleCase(tourism || leisure || 'place'),
      icon: tourism === 'museum' ? 'museum' : 'attraction',
    };
  }

  if (shop) {
    return {
      group: 'Shopping',
      subcategory: titleCase(shop),
      icon: 'shop',
    };
  }

  if (amenity === 'fuel' || amenity === 'parking' || amenity === 'car_rental') {
    return {
      group: 'Transport',
      subcategory: titleCase(amenity),
      icon: amenity === 'fuel' ? 'fuel' : 'transport',
    };
  }

  if (amenity || tags.office) {
    return {
      group: 'Services',
      subcategory: titleCase(amenity || tags.office),
      icon: 'service',
    };
  }

  if (tags['addr:street'] || tags['addr:housenumber']) {
    return {
      group: 'Address',
      subcategory: 'Address',
      icon: 'address',
    };
  }

  return {
    group: 'Places',
    subcategory: 'Place',
    icon: 'place',
  };
}

function titleCase(value) {
  return String(value || 'Place')
    .replace(/_/g, ' ')
    .replace(/\b\w/g, (char) => char.toUpperCase());
}

function displayCategory(tags) {
  return placeClassification(tags).subcategory;
}

function legacyDisplayCategory(tags) {
  if (tags.shop) return `Shop: ${tags.shop}`;
  if (tags.amenity) return `Amenity: ${tags.amenity}`;
  if (tags.office) return `Office: ${tags.office}`;
  if (tags.tourism) return `Tourism: ${tags.tourism}`;
  if (tags.leisure) return `Leisure: ${tags.leisure}`;
  if (tags['addr:street'] || tags['addr:housenumber']) return 'Address';
  return 'Place';
}

function entryKind(tags) {
  if (tags.shop || tags.amenity || tags.office || tags.tourism || tags.leisure) {
    return 'store';
  }
  if (tags['addr:street'] || tags['addr:housenumber']) {
    return 'address';
  }
  return 'place';
}

function entryLabel(tags) {
  const addressParts = [tags['addr:street'], tags['addr:housenumber']]
    .filter(Boolean)
    .join(' ');
  return addressParts || tags.name || tags['addr:street'] || tags['addr:housenumber'];
}

function entryAddress(tags) {
  return [tags['addr:street'], tags['addr:housenumber'], tags['addr:postcode']]
    .filter(Boolean)
    .join(' ');
}

function isSearchable(tags) {
  return Boolean(
    tags.name ||
      tags['addr:street'] ||
      tags['addr:housenumber'] ||
      tags.shop ||
      tags.amenity ||
      tags.office ||
      tags.tourism ||
      tags.leisure
  );
}

function addSearchEntry(sourceType, sourceId, tags, lat, lon) {
  if (!inNuuk(lat, lon) || !isSearchable(tags)) return;

  const label = entryLabel(tags);
  if (!label) return;

  const address = entryAddress(tags);
  const classification = placeClassification(tags);
  const aliases = [
    label,
    tags.name,
    tags['name:kl'],
    tags['name:da'],
    tags['name:en'],
    tags['addr:street'],
    tags['addr:housenumber'],
    address,
    classification.group,
    classification.subcategory,
    legacyDisplayCategory(tags),
    tags.shop,
    tags.amenity,
  ].filter(Boolean);

  const key = `${sourceType}/${sourceId}/${normalize(label)}/${lat.toFixed(6)}/${lon.toFixed(6)}`;
  searchEntries.set(key, {
    id: key,
    kind: entryKind(tags),
    label,
    category: displayCategory(tags),
    group: classification.group,
    subcategory: classification.subcategory,
    icon: classification.icon,
    address,
    latitude: Number(lat.toFixed(7)),
    longitude: Number(lon.toFixed(7)),
    searchText: normalize(aliases.join(' ')),
  });
}

function isDrivableWay(tags) {
  if (!drivableHighways.has(tags.highway)) return false;
  if (tags.access === 'no' || tags.motor_vehicle === 'no') return false;
  if (tags.area === 'yes') return false;
  return true;
}

function distanceMeters(a, b) {
  const earthRadius = 6371000;
  const lat1 = (a.lat * Math.PI) / 180;
  const lat2 = (b.lat * Math.PI) / 180;
  const deltaLat = ((b.lat - a.lat) * Math.PI) / 180;
  const deltaLon = ((b.lon - a.lon) * Math.PI) / 180;
  const h =
    Math.sin(deltaLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(deltaLon / 2) ** 2;
  return 2 * earthRadius * Math.asin(Math.sqrt(h));
}

function addRouteEdge(fromId, toId, name) {
  const from = routeNodes.get(fromId);
  const to = routeNodes.get(toId);
  if (!from || !to) return;

  const distance = distanceMeters(from, to);
  if (!routeEdges.has(fromId)) routeEdges.set(fromId, []);
  if (!routeEdges.has(toId)) routeEdges.set(toId, []);
  routeEdges.get(fromId).push({ to: String(toId), distance, name });
  routeEdges.get(toId).push({ to: String(fromId), distance, name });
}

function wayCenter(refs) {
  const coords = refs.map((ref) => nodeCoordinates.get(ref)).filter(Boolean);
  if (coords.length === 0) return null;
  const totals = coords.reduce(
    (sum, coord) => ({ lat: sum.lat + coord.lat, lon: sum.lon + coord.lon }),
    { lat: 0, lon: 0 }
  );
  return { lat: totals.lat / coords.length, lon: totals.lon / coords.length };
}

fs.createReadStream(pbfPath)
  .pipe(parseOSM())
  .pipe(
    through.obj((items, enc, next) => {
      for (const item of items) {
        if (item.type === 'node' && inNuuk(item.lat, item.lon)) {
          nodeCoordinates.set(item.id, { lat: item.lat, lon: item.lon });
          addSearchEntry('node', item.id, item.tags || {}, item.lat, item.lon);
          continue;
        }

        if (item.type !== 'way') continue;
        const tags = item.tags || {};
        const center = wayCenter(item.refs || []);
        if (center) {
          addSearchEntry('way', item.id, tags, center.lat, center.lon);
        }

        if (!isDrivableWay(tags)) continue;
        if (tags.name) streetNames.add(tags.name);

        const refs = item.refs || [];
        for (const ref of refs) {
          const coord = nodeCoordinates.get(ref);
          if (coord) routeNodes.set(ref, coord);
        }

        for (let index = 0; index < refs.length - 1; index++) {
          addRouteEdge(refs[index], refs[index + 1], tags.name || 'Road');
        }
      }
      next();
    })
  )
  .on('finish', () => {
    fs.mkdirSync(outputDir, { recursive: true });

    const sortedEntries = Array.from(searchEntries.values()).sort((a, b) => {
      if (a.kind !== b.kind) return a.kind.localeCompare(b.kind);
      return a.label.localeCompare(b.label);
    });

    const graphNodes = Array.from(routeNodes.entries()).map(([id, coord]) => ({
      id: String(id),
      latitude: Number(coord.lat.toFixed(7)),
      longitude: Number(coord.lon.toFixed(7)),
    }));

    const graphEdges = Array.from(routeEdges.entries()).flatMap(([from, edges]) =>
      edges.map((edge) => ({
        from: String(from),
        to: edge.to,
        distance: Number(edge.distance.toFixed(2)),
        name: edge.name,
      }))
    );

    fs.writeFileSync(
      path.join(outputDir, 'nuuk_search_index.json'),
      JSON.stringify(
        {
          generatedAt: new Date().toISOString(),
          bounds,
          entries: sortedEntries,
          streetNames: Array.from(streetNames).sort(),
        },
        null,
        2
      )
    );

    fs.writeFileSync(
      path.join(outputDir, 'nuuk_route_graph.json'),
      JSON.stringify(
        {
          generatedAt: new Date().toISOString(),
          bounds,
          nodes: graphNodes,
          edges: graphEdges,
        },
        null,
        2
      )
    );

    console.log(`Extracted ${sortedEntries.length} search entries`);
    console.log(`Extracted ${graphNodes.length} route nodes and ${graphEdges.length} directed edges`);
  });