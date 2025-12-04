let bleCharacteristic: BluetoothRemoteGATTCharacteristic | null = null

export function setBleCharacteristic(
  characteristic: BluetoothRemoteGATTCharacteristic | null,
) {
  bleCharacteristic = characteristic
}

export function getBleCharacteristic(): BluetoothRemoteGATTCharacteristic | null {
  return bleCharacteristic
}


