# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Automation body-variant bay envelopes, in metres (not stock block sizes).

Automation stores four side-profile points in centimetres, mirrored in X.
Use an inscribed rectangular envelope: the narrowest half-width and lowest
roof, not the larger outer AABB of a sloped bay. This is a dimensional fit
screen, not a collision survey of accessories, mounts or the final morphed mesh.
"""
import math
import re

PLACEMENTS = {
    'EngPlace_FrLong_Name': ('FrontEngineBounds', -90),
    'EngPlace_FrTransverse_Name': ('FrontEngineBounds', 0),
    'EngPlace_MidLong_Name': ('MidEngineBounds', -90),
    'EngPlace_MidTransverse_Name': ('MidEngineBounds', 0),
    'EngPlace_RearLong_Name': ('RearEngineBounds', 90),
}
CLEARANCE_M = 0.02  # dimensional allowance on each side; not an OEM specification


def vector(value, length):
    if not isinstance(value, dict) or set(value) != set(range(1, length + 1)):
        raise ValueError('expected a one-based vector')
    result = [value[i] for i in range(1, length + 1)]
    if any(isinstance(x, bool) or not isinstance(x, (int, float)) or not math.isfinite(x) for x in result):
        raise ValueError('nonfinite/non-numeric bay coordinate')
    return result


def measure(design):
    """Always return an audit record; incomplete data never loosens a fit."""
    result = {'available': False, 'units': 'm', 'sourceUnits': 'cm'}
    try:
        trim, model = design.get('Trim', {}), design.get('Model', {})
        placement = model.get('EnginePlacement')
        result['placement'] = placement
        if placement not in PLACEMENTS:
            raise ValueError('unsupported/missing engine placement')
        key, yaw = PLACEMENTS[placement]
        # BodyFamily may describe a different saloon/coupe variant. Do not
        # substitute its roomier dimensions when the actual variant is present.
        body = trim.get('BodyVariant')
        source = 'Trim.BodyVariant'
        if not isinstance(body, dict) or not body:
            raise ValueError('missing body-variant bay data')
        result.update({'source': source + '.' + key, 'bodyUID': body.get('UID'),
                       'bodyName': body.get('Name')})
        points = [vector(v, 3) for v in vector_tables(body.get(key))]
        engine_point = vector(trim.get('EnginePoint'), 4)
        if abs(engine_point[3] - yaw) > 1e-5:
            raise ValueError('engine yaw does not match placement')
        # Exported body bays have two roof points followed by two floor points,
        # forming a side-profile quadrilateral. Reject unknown topology.
        top = sorted(points[:2], key=lambda p: p[1])
        bottom = sorted(points[2:], key=lambda p: p[1])
        if any(abs(a[1] - b[1]) > 1e-4 for a, b in zip(top, bottom)):
            raise ValueError('unsupported bay side-profile topology')
        width = min(p[0] for p in points) * 2 / 100
        length = (top[1][1] - top[0][1]) / 100
        floor = max(p[2] for p in bottom) / 100
        roof = min(p[2] for p in top) / 100
        size = [width, length, roof - floor]
        if any(v <= 2 * CLEARANCE_M or v > 5 for v in size):
            raise ValueError('invalid/degenerate bay dimensions')
        if any(t[2] <= b[2] for t, b in zip(top, bottom)):
            raise ValueError('inverted bay roof/floor')
        enabled = body.get('TrimEngineTypes', body.get('EngineTypes', {}))
        location = key.removesuffix('EngineBounds').upper()
        if enabled and enabled.get(location) is not True:
            raise ValueError('engine location disabled for this body variant')
        result.update({'available': True, 'sizeXYZ': size,
            'rawSidePointsCM': points, 'enginePointCM': engine_point,
            'yawDegrees': yaw, 'clearancePerSideM': CLEARANCE_M,
            'usableSizeXYZ': [v - 2 * CLEARANCE_M for v in size],
            'boundsXY': [[-width / 2, -top[1][1] / 100],
                         [width / 2, -top[0][1] / 100]],
            'roofRangeM': [min(p[2] for p in top) / 100, max(p[2] for p in top) / 100],
            'scope': 'Bay dimensions and stock-centred XY placement; absolute Z, accessories and final mesh clearance unverified'})
    except (ValueError, KeyError, TypeError) as error:
        result.update({'available': False, 'reason': str(error)})
    return result


def vector_tables(value):
    if not isinstance(value, dict) or set(value) != {1, 2, 3, 4}:
        raise ValueError('expected four bay side-profile points')
    return [value[i] for i in range(1, 5)]


def verify_frame(bay, design, front_text, rear_text):
    """Verify cm->m and the Y reflection against both exported wheel axles.

The mesh wheel positions are already in the same model frame as engine nodes.
No world/spawn Z offset is inferred from these two horizontal landmarks.
"""
    result = dict(bay)
    if not result.get('available'):
        return result
    try:
        body = design['Trim']['BodyVariant']
        errors = []
        axles = []
        for text, group, key in [(front_text, 'wheel_FL', 'FrontAxleYPosition'),
                                  (rear_text, 'wheel_RL', 'RearAxleYPosition')]:
            row = next(line for line in text.splitlines()
                       if re.search(r'\[\s*"' + group + r'"\s*,', line) and '"pos"' in line)
            pos = re.search(r'"pos"\s*:\s*\{[^}]*"y"\s*:\s*([-+\d.eE]+)', row)
            actual = float(pos[1])
            expected = -float(body[key]) / 100
            errors.append(abs(actual - expected))
            axles.append(actual)
        wheelbase = abs(axles[0] - axles[1])
        expected = float(body['WheelBase']) / 100
        errors.append(abs(wheelbase - expected))
        if any(not math.isfinite(v) or v > 0.002 for v in errors):
            raise ValueError('body/wheel coordinates disagree by more than 2 mm')
        result['frameCheck'] = {'passed': True, 'wheelbaseM': wheelbase,
            'bodyWheelbaseM': expected, 'maxErrorM': max(errors),
            'mapping': 'Automation cm to BeamNG m: x/100, -y/100; absolute Z not established'}
    except (StopIteration, KeyError, TypeError, ValueError) as error:
        result.update({'available': False, 'reason': 'Unverified bay coordinate frame: ' + str(error)})
    return result


def rotate(point, degrees):
    """Quarter turns only; no trig noise or arbitrary angle broadening."""
    x, y, z = point
    turns = degrees / 90
    if abs(turns - round(turns)) > 1e-8:
        raise ValueError('unsupported engine orientation')
    for _ in range(round(turns) % 4):
        x, y = -y, x
    return [x, y, z]


def fit(recipient, donor):
    """Shared by the shop catalogue and the part builder; no bypass flag."""
    rg, dg = recipient['engineGeometry'], donor['engineGeometry']
    for shape in (rg, dg):
        try:
            nodes = shape['nodes']
            if len(nodes) != 8 or {n['id'] for n in nodes} != {'engine' + str(i) for i in range(8)}:
                raise ValueError('expected eight block corners')
            if any(len(shape[key]) != 3 for key in ('low', 'high', 'sizeXYZ')):
                raise ValueError('invalid block bounds')
            coords = [n['pos'] for n in nodes]
            if any(len(p) != 3 or any(not math.isfinite(v) for v in p) for p in coords):
                raise ValueError('invalid block coordinates')
            low = [min(p[i] for p in coords) for i in range(3)]
            high = [max(p[i] for p in coords) for i in range(3)]
            if any(b <= a for a, b in zip(low, high)):
                raise ValueError('degenerate engine block')
            if any(abs(a - b) > 1e-8 for a, b in zip(low + high + [b - a for a, b in zip(low, high)],
                                                       shape['low'] + shape['high'] + shape['sizeXYZ'])):
                raise ValueError('inconsistent block bounds')
        except (ValueError, KeyError, TypeError) as error:
            return {'accepted': False, 'method': 'invalid-geometry',
                    'reason': 'Fit not established: ' + str(error)}
    bay, donor_bay = recipient.get('engineBay', {}), donor.get('engineBay', {})
    method = 'stock-block-fallback'
    yaw = 0
    limit = rg['sizeXYZ']
    fallback_reason = bay.get('reason', 'bay metadata unavailable')
    if bay.get('available') and donor_bay.get('available'):
        # A stock export already outside this dimensional envelope cannot
        # establish the mapping. Keep its historical conservative fallback.
        low, high = bay['boundsXY']
        stock_xy_inside = all(low[i] - 1e-5 <= n['pos'][i] <= high[i] + 1e-5
                              for n in rg['nodes'] for i in range(2))
        if stock_xy_inside and all(a <= b + 1e-8 for a, b in zip(rg['sizeXYZ'], bay['sizeXYZ'])):
            method = 'automation-bay-envelope'
            # Automation +Y forward becomes BeamNG -Y forward.
            yaw = donor_bay['yawDegrees'] - bay['yawDegrees']
            limit = bay['usableSizeXYZ']
        else:
            fallback_reason = 'stock block exceeds body-variant envelope/XY bounds; mapping unverified'
    elif bay.get('available'):
        fallback_reason = 'donor orientation metadata unavailable'
    centre = [(a + b) / 2 for a, b in zip(dg['low'], dg['high'])]
    rc = [(a + b) / 2 for a, b in zip(rg['low'], rg['high'])]
    rotated = [rotate([p - c for p, c in zip(n['pos'], centre)], yaw) for n in dg['nodes']]
    size = [max(p[i] for p in rotated) - min(p[i] for p in rotated) for i in range(3)]
    accepted = all(a <= b + 1e-8 for a, b in zip(size, limit))
    placed = [{**n, 'pos': [a + b for a, b in zip(p, rc)]}
              for n, p in zip(dg['nodes'], rotated)]
    xy_ok = True
    if method == 'automation-bay-envelope':
        low, high = bay['boundsXY']
        xy_ok = all(low[i] + CLEARANCE_M - 1e-8 <= n['pos'][i] <= high[i] - CLEARANCE_M + 1e-8
                    for n in placed for i in range(2))
        accepted = accepted and xy_ok
    result = {'accepted': accepted, 'method': method, 'rotationDegrees': yaw,
              'donorOrientedSizeXYZ': size, 'limitSizeXYZ': limit,
              'donorCentreXYZ': centre, 'recipientCentreXYZ': rc,
              'positionOffsetXYZ': [a - b for a, b in zip(rc, rotate(centre, yaw))],
              'nodes': placed}
    if method == 'stock-block-fallback':
        result['fallbackReason'] = fallback_reason
    if not accepted:
        axes = [name for name, a, b in zip(('width', 'length', 'height'), size, limit) if a > b + 1e-8]
        if not xy_ok:
            axes.append('clearance at the original mounting position')
        result['reason'] = ('Fit not established: donor exceeds ' +
            ('Automation bay ' if method == 'automation-bay-envelope' else 'original block ') + '/'.join(axes))
    return result
