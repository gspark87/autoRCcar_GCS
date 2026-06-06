// lib/math/user_geometry.dart
// user_geometry.py 의 Dart 포팅

import 'dart:math';

/// Quaternion (w,x,y,z) → Euler angles (roll, pitch, yaw) [rad]
List<double> quat2euler(List<double> quat) {
  // normalize
  double norm = sqrt(quat[0] * quat[0] +
      quat[1] * quat[1] +
      quat[2] * quat[2] +
      quat[3] * quat[3]);
  double a = quat[0] / norm;
  double b = quat[1] / norm;
  double c = quat[2] / norm;
  double d = quat[3] / norm;

  double A = 2 * (a * b + c * d);
  double B = a * a - b * b - c * c + d * d;
  double C = 2 * (b * d - a * c);
  double D = 2 * (a * d + b * c);
  double E = a * a + b * b - c * c - d * d;

  double phi = atan2(A, B);
  double theta = asin(-C.clamp(-1.0, 1.0));
  double psi = atan2(D, E);

  return [phi, theta, psi]; // rad [roll, pitch, yaw]
}

const double _aa = 6378317.0;
const double _ee = 0.0818191908426;

/// LLH (rad) → NED [m], origin도 rad
List<double> llh2ned(List<double> llh, List<double> llhOri) {
  double lat = llh[0];
  double lon = llh[1];
  double hei = llh[2];
  double latOri = llhOri[0];
  double heiOri = llhOri[2];

  double rtmp = 1 - _ee * _ee * sin(latOri) * sin(latOri);
  double rm = _aa * (1 - _ee * _ee) / pow(rtmp, 1.5);
  double rn = _aa / sqrt(rtmp);

  double n = (rm + hei) * (lat - latOri);
  double e = (rn + hei) * cos(lat) * (lon - llhOri[1]);
  double d = -(hei - heiOri);

  return [n, e, d];
}

/// NED [m] → LLH (rad), origin도 rad
List<double> ned2llh(List<double> ned, List<double> llhOri) {
  double n = ned[0];
  double e = ned[1];
  double d = ned[2];
  double latOri = llhOri[0];
  double heiOri = llhOri[2];

  double rtmp = 1 - _ee * _ee * sin(latOri) * sin(latOri);
  double rm = _aa * (1 - _ee * _ee) / pow(rtmp, 1.5);
  double rn = _aa / sqrt(rtmp);

  double hei = -d + heiOri;
  double lat = n / (rm + hei) + latOri;
  double lon = e / ((rn + hei) * cos(lat)) + llhOri[1];

  return [lat, lon, hei];
}

/// ENU [m] → LLH (rad), origin은 rad
/// ENU = (East, North, Up), NED = (North, East, Down)
List<double> enu2llh(List<double> enu, List<double> llhOri) {
  // ENU → NED 변환
  List<double> ned = [enu[1], enu[0], -enu[2]];
  return ned2llh(ned, llhOri);
}

/// LLH (rad) → ENU [m]
List<double> llh2enu(List<double> llh, List<double> llhOri) {
  List<double> ned = llh2ned(llh, llhOri);
  // NED → ENU
  return [ned[1], ned[0], -ned[2]];
}

/// deg → rad
double deg2rad(double deg) => deg * pi / 180.0;

/// rad → deg
double rad2deg(double rad) => rad * 180.0 / pi;
