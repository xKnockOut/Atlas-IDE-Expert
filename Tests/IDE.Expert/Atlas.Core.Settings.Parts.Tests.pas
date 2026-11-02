unit Atlas.Core.Settings.Parts.Tests;

// Einstellungsteile der Module in Base (#1455, ADR 0017 Entscheidung 3):
// Vorgaben, Lesen und Schreiben, Werte fremder und fehlender Module,
// Umbenennungen, Ablagewechsel, Vergessen eines Moduls, Änderungsmeldung und
// Lösen über den Scope eines Moduls.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TSettingsPartsTests = class
  public
    [Test]
    procedure DefaultsWithoutStoredValue;
    [Test]
    procedure WriteAndReadBack;
    [Test]
    procedure InvalidStoredValueGivesDefault;
    [Test]
    procedure IntegerStaysInRange;
    [Test]
    procedure ResetRestoresDefault;
    [Test]
    procedure UnknownKeyAndWrongKindRaise;
    [Test]
    procedure RejectsBrokenParts;
    [Test]
    procedure RemovedPartKeepsValues;
    [Test]
    procedure ForeignValuesStay;
    [Test]
    procedure UseStorageMovesMemoryValues;
    [Test]
    procedure RenameMovesValue;
    [Test]
    procedure RenameKeepsExistingNewValue;
    [Test]
    procedure RenameAppliedOnUseStorage;
    [Test]
    procedure RejectsRenameOfRegisteredKey;
    [Test]
    procedure ForgetOwnerRemovesEveryKeyEverRegistered;
    [Test]
    procedure ForgetOwnerRefusesRegisteredModule;
    [Test]
    procedure ListenerSeesChanges;
    [Test]
    procedure RevokedListenerIsNotCalled;
    [Test]
    procedure ModuleScopeRemovesPart;
    [Test]
    procedure MemoryStorageSortsNames;
    [Test]
    procedure GlobalPartsExist;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Settings.Contract,
  Atlas.Core.Settings.Parts;

type
  TFakePart = class(TInterfacedObject, IAtlasSettingsPart)
  private
    FOwnerId: string;
    FKeys: TArray<TAtlasSettingsKey>;
    FRenames: TArray<TAtlasSettingsKeyRename>;
  public
    constructor Create(const AOwnerId: string);
    procedure AddKey(const AKey: string; AKind: TAtlasSettingsValueKind; const ADefault: string); overload;
    procedure AddKey(const AKey: string; const ADefault: string; AMinimum, AMaximum: Integer); overload;
    procedure AddRename(const AOldKey, ANewKey: string);
    function OwnerId: string;
    function Page: TAtlasSettingsPageInfo;
    function Keys: TArray<TAtlasSettingsKey>;
    function SchemaPart: string;
    function Renames: TArray<TAtlasSettingsKeyRename>;
  end;

  TLogListener = class(TInterfacedObject, IAtlasSettingsListener)
  public
    Text: string;
    procedure SettingsChanged(const AChange: TAtlasSettingsChange);
  end;

  TFakeModule = class(TInterfacedObject, IAtlasModule)
  private
    FId: string;
  public
    constructor Create(const AId: string);
    function Info: TAtlasModuleInfo;
    procedure Start;
    procedure Stop;
    function IsActive: Boolean;
  end;

const
  cKindNames: array[TAtlasSettingsChangeKind] of string = ('added', 'removed', 'value', 'renamed', 'storage',
    'forgotten');

{ TFakePart }

constructor TFakePart.Create(const AOwnerId: string);
begin
  inherited Create;
  FOwnerId := AOwnerId;
end;

procedure TFakePart.AddKey(const AKey: string; AKind: TAtlasSettingsValueKind; const ADefault: string);
var
  mKey: TAtlasSettingsKey;
begin
  mKey := Default(TAtlasSettingsKey);
  mKey.Key := AKey;
  mKey.Kind := AKind;
  mKey.Default := ADefault;
  mKey.Minimum := 1;
  mKey.Maximum := 0;
  FKeys := FKeys + [mKey];
end;

procedure TFakePart.AddKey(const AKey: string; const ADefault: string; AMinimum, AMaximum: Integer);
var
  mKey: TAtlasSettingsKey;
begin
  mKey := Default(TAtlasSettingsKey);
  mKey.Key := AKey;
  mKey.Kind := svInteger;
  mKey.Default := ADefault;
  mKey.Minimum := AMinimum;
  mKey.Maximum := AMaximum;
  FKeys := FKeys + [mKey];
end;

procedure TFakePart.AddRename(const AOldKey, ANewKey: string);
var
  mRename: TAtlasSettingsKeyRename;
begin
  mRename.OldKey := AOldKey;
  mRename.NewKey := ANewKey;
  FRenames := FRenames + [mRename];
end;

function TFakePart.OwnerId: string;
begin
  Result := FOwnerId;
end;

function TFakePart.Page: TAtlasSettingsPageInfo;
begin
  Result.Id := FOwnerId;
  Result.Caption := 'Seite ' + FOwnerId;
  Result.Parent := '';
end;

function TFakePart.Keys: TArray<TAtlasSettingsKey>;
begin
  Result := FKeys;
end;

function TFakePart.SchemaPart: string;
begin
  Result := '{}';
end;

function TFakePart.Renames: TArray<TAtlasSettingsKeyRename>;
begin
  Result := FRenames;
end;

{ TLogListener }

procedure TLogListener.SettingsChanged(const AChange: TAtlasSettingsChange);
begin
  if Text <> '' then
  begin
    Text := Text + ' ';
  end;
  Text := Text + cKindNames[AChange.Kind] + ':' + AChange.OwnerId + ':' + AChange.Key;
  if AChange.OldKey <> '' then
  begin
    Text := Text + '<' + AChange.OldKey;
  end;
end;

{ TFakeModule }

constructor TFakeModule.Create(const AId: string);
begin
  inherited Create;
  FId := AId;
end;

function TFakeModule.Info: TAtlasModuleInfo;
begin
  Result := Default(TAtlasModuleInfo);
  Result.Id := FId;
end;

procedure TFakeModule.Start;
begin
end;

procedure TFakeModule.Stop;
begin
end;

function TFakeModule.IsActive: Boolean;
begin
  Result := False;
end;

function DebuggerPart: TFakePart;
begin
  Result := TFakePart.Create('atlas.debugger');
  Result.AddKey('debug.enabled', svBoolean, '1');
  Result.AddKey('debug.depth', '3', 1, 10);
  Result.AddKey('debug.filter', svString, 'System.*');
end;

{ TSettingsPartsTests }

procedure TSettingsPartsTests.DefaultsWithoutStoredValue;
var
  mParts: IAtlasSettingsParts;
  mKey: TAtlasSettingsKey;
begin
  mParts := TAtlasSettingsParts.Create;
  mParts.Add(DebuggerPart as IAtlasSettingsPart);
  Assert.IsTrue(mParts.Values.ReadBoolean('debug.enabled'));
  Assert.AreEqual(3, mParts.Values.ReadInteger('debug.depth'));
  Assert.AreEqual('System.*', mParts.Values.ReadString('debug.filter'));
  Assert.IsFalse(mParts.Values.Contains('debug.enabled'));
  Assert.IsTrue(mParts.FindKey('debug.depth', mKey));
  Assert.AreEqual(10, mKey.Maximum);
  Assert.IsFalse(mParts.FindKey('debug.nix', mKey));
  Assert.AreEqual(1, Integer(Length(mParts.Parts)));
end;

procedure TSettingsPartsTests.WriteAndReadBack;
var
  mStorage: IAtlasSettingsStorage;
  mParts: IAtlasSettingsParts;
  mKeys: TArray<string>;
begin
  mStorage := TAtlasMemorySettingsStorage.Create;
  mParts := TAtlasSettingsParts.Create(mStorage);
  mParts.Add(DebuggerPart as IAtlasSettingsPart);
  mParts.Values.WriteBoolean('debug.enabled', False);
  mParts.Values.WriteInteger('debug.depth', 7);
  mParts.Values.WriteString('debug.filter', 'Vcl.*');
  Assert.IsFalse(mParts.Values.ReadBoolean('debug.enabled'));
  Assert.AreEqual(7, mParts.Values.ReadInteger('debug.depth'));
  Assert.AreEqual('Vcl.*', mParts.Values.ReadString('debug.filter'));
  Assert.AreEqual('0', mStorage.ReadText('debug.enabled'));
  Assert.AreEqual('7', mStorage.ReadText('debug.depth'));
  mKeys := mParts.Values.StoredKeys;
  // Ohne die Verwaltungsdaten von Base ($parts.…).
  Assert.AreEqual(3, Integer(Length(mKeys)));
  Assert.AreEqual('debug.depth', mKeys[0]);
  Assert.AreEqual('debug.enabled', mKeys[1]);
  Assert.AreEqual('debug.filter', mKeys[2]);
end;

procedure TSettingsPartsTests.InvalidStoredValueGivesDefault;
var
  mStorage: IAtlasSettingsStorage;
  mParts: IAtlasSettingsParts;
begin
  mStorage := TAtlasMemorySettingsStorage.Create;
  mStorage.WriteText('debug.enabled', 'vielleicht');
  mStorage.WriteText('debug.depth', 'drei');
  mParts := TAtlasSettingsParts.Create(mStorage);
  mParts.Add(DebuggerPart as IAtlasSettingsPart);
  Assert.IsTrue(mParts.Values.ReadBoolean('debug.enabled'));
  Assert.AreEqual(3, mParts.Values.ReadInteger('debug.depth'));
  mStorage.WriteText('debug.enabled', 'false');
  Assert.IsFalse(mParts.Values.ReadBoolean('debug.enabled'));
end;

procedure TSettingsPartsTests.IntegerStaysInRange;
var
  mStorage: IAtlasSettingsStorage;
  mParts: IAtlasSettingsParts;
begin
  mStorage := TAtlasMemorySettingsStorage.Create;
  mParts := TAtlasSettingsParts.Create(mStorage);
  mParts.Add(DebuggerPart as IAtlasSettingsPart);
  mParts.Values.WriteInteger('debug.depth', 99);
  Assert.AreEqual('10', mStorage.ReadText('debug.depth'));
  mStorage.WriteText('debug.depth', '-5');
  Assert.AreEqual(1, mParts.Values.ReadInteger('debug.depth'));
end;

procedure TSettingsPartsTests.ResetRestoresDefault;
var
  mParts: IAtlasSettingsParts;
begin
  mParts := TAtlasSettingsParts.Create;
  mParts.Add(DebuggerPart as IAtlasSettingsPart);
  mParts.Values.WriteInteger('debug.depth', 5);
  mParts.Values.Reset('debug.depth');
  Assert.IsFalse(mParts.Values.Contains('debug.depth'));
  Assert.AreEqual(3, mParts.Values.ReadInteger('debug.depth'));
end;

procedure TSettingsPartsTests.UnknownKeyAndWrongKindRaise;
var
  mParts: IAtlasSettingsParts;
  mUnknown: Boolean;
  mWrongKind: Boolean;
  mWrongWrite: Boolean;
begin
  mParts := TAtlasSettingsParts.Create;
  mParts.Add(DebuggerPart as IAtlasSettingsPart);
  mUnknown := False;
  try
    mParts.Values.ReadBoolean('debug.nix');
  except
    on EAtlasSettingsKey do
      mUnknown := True;
  end;
  mWrongKind := False;
  try
    mParts.Values.ReadInteger('debug.enabled');
  except
    on EAtlasSettingsKey do
      mWrongKind := True;
  end;
  mWrongWrite := False;
  try
    mParts.Values.WriteString('debug.depth', 'x');
  except
    on EAtlasSettingsKey do
      mWrongWrite := True;
  end;
  Assert.IsTrue(mUnknown, 'unbekannt');
  Assert.IsTrue(mWrongKind, 'falsche Art beim Lesen');
  Assert.IsTrue(mWrongWrite, 'falsche Art beim Schreiben');
  Assert.IsFalse(mParts.Values.Contains('debug.depth'));
end;

procedure TSettingsPartsTests.RejectsBrokenParts;
var
  mParts: IAtlasSettingsParts;
  mPart: TFakePart;
  mCount: Integer;
begin
  mParts := TAtlasSettingsParts.Create;
  mParts.Add(DebuggerPart as IAtlasSettingsPart);
  mCount := 0;
  // Schlüssel eines anderen Moduls.
  mPart := TFakePart.Create('atlas.tracker');
  mPart.AddKey('debug.enabled', svBoolean, '0');
  try
    mParts.Add(mPart as IAtlasSettingsPart);
  except
    on EAtlasSettingsParts do
      Inc(mCount);
  end;
  // Ohne Besitzer.
  mPart := TFakePart.Create(' ');
  mPart.AddKey('x.y', svBoolean, '0');
  try
    mParts.Add(mPart as IAtlasSettingsPart);
  except
    on EAtlasSettingsParts do
      Inc(mCount);
  end;
  // Name der Verwaltungsdaten.
  mPart := TFakePart.Create('atlas.tracker');
  mPart.AddKey('$parts.x', svString, '');
  try
    mParts.Add(mPart as IAtlasSettingsPart);
  except
    on EAtlasSettingsParts do
      Inc(mCount);
  end;
  // Doppelt im selben Teil.
  mPart := TFakePart.Create('atlas.tracker');
  mPart.AddKey('issues.a', svString, '');
  mPart.AddKey('issues.a', svString, '');
  try
    mParts.Add(mPart as IAtlasSettingsPart);
  except
    on EAtlasSettingsParts do
      Inc(mCount);
  end;
  Assert.AreEqual(4, mCount);
  Assert.AreEqual(1, Integer(Length(mParts.Parts)));
end;

procedure TSettingsPartsTests.RemovedPartKeepsValues;
var
  mStorage: IAtlasSettingsStorage;
  mParts: IAtlasSettingsParts;
  mRegistration: IAtlasRegistration;
  mRaised: Boolean;
begin
  mStorage := TAtlasMemorySettingsStorage.Create;
  mParts := TAtlasSettingsParts.Create(mStorage);
  mRegistration := mParts.Add(DebuggerPart as IAtlasSettingsPart);
  mParts.Values.WriteInteger('debug.depth', 5);
  mRegistration.Revoke;
  Assert.AreEqual(0, Integer(Length(mParts.Parts)));
  Assert.AreEqual('5', mStorage.ReadText('debug.depth'));
  Assert.IsTrue(mParts.Values.Contains('debug.depth'));
  mRaised := False;
  try
    mParts.Values.ReadInteger('debug.depth');
  except
    on EAtlasSettingsKey do
      mRaised := True;
  end;
  Assert.IsTrue(mRaised, 'ohne Teil nicht lesbar');
  // Wieder angemeldet: derselbe Wert.
  mParts.Add(DebuggerPart as IAtlasSettingsPart);
  Assert.AreEqual(5, mParts.Values.ReadInteger('debug.depth'));
end;

procedure TSettingsPartsTests.ForeignValuesStay;
var
  mStorage: IAtlasSettingsStorage;
  mParts: IAtlasSettingsParts;
  mKeys: TArray<string>;
begin
  mStorage := TAtlasMemorySettingsStorage.Create;
  mStorage.WriteText('fremd.wert', 'bleibt');
  mParts := TAtlasSettingsParts.Create(mStorage);
  mParts.Add(DebuggerPart as IAtlasSettingsPart);
  mParts.Values.WriteBoolean('debug.enabled', False);
  mKeys := mParts.Values.StoredKeys;
  Assert.AreEqual(2, Integer(Length(mKeys)));
  Assert.AreEqual('debug.enabled', mKeys[0]);
  Assert.AreEqual('fremd.wert', mKeys[1]);
  Assert.AreEqual('bleibt', mStorage.ReadText('fremd.wert'));
end;

procedure TSettingsPartsTests.UseStorageMovesMemoryValues;
var
  mStorage: IAtlasSettingsStorage;
  mParts: IAtlasSettingsParts;
  mListener: TLogListener;
  mListenerRef: IAtlasSettingsListener;
begin
  mParts := TAtlasSettingsParts.Create;
  mParts.Add(DebuggerPart as IAtlasSettingsPart);
  mParts.Values.WriteInteger('debug.depth', 4);
  mParts.Values.WriteString('debug.filter', 'nur im Speicher');
  mStorage := TAtlasMemorySettingsStorage.Create;
  mStorage.WriteText('debug.filter', 'gespeichert');
  mListener := TLogListener.Create;
  mListenerRef := mListener;
  mParts.Subscribe(mListenerRef);
  mParts.UseStorage(mStorage);
  Assert.AreEqual('4', mStorage.ReadText('debug.depth'));
  // Gespeicherte Werte der neuen Ablage gelten.
  Assert.AreEqual('gespeichert', mParts.Values.ReadString('debug.filter'));
  Assert.IsTrue(mStorage.Contains(cAtlasOwnerKeysPrefix + 'atlas.debugger' + cAtlasOwnerKeysSuffix));
  Assert.AreEqual('storage::', mListener.Text);
end;

procedure TSettingsPartsTests.RenameMovesValue;
var
  mStorage: IAtlasSettingsStorage;
  mParts: IAtlasSettingsParts;
  mPart: TFakePart;
begin
  mStorage := TAtlasMemorySettingsStorage.Create;
  mStorage.WriteText('welcomePage.issues.query', 'assignee:me');
  mParts := TAtlasSettingsParts.Create(mStorage);
  mPart := TFakePart.Create('atlas.tracker');
  mPart.AddKey('issues.query', svString, '');
  mPart.AddRename('welcomePage.issues.query', 'issues.query');
  mParts.Add(mPart as IAtlasSettingsPart);
  Assert.AreEqual('assignee:me', mParts.Values.ReadString('issues.query'));
  Assert.IsFalse(mStorage.Contains('welcomePage.issues.query'));
end;

procedure TSettingsPartsTests.RenameKeepsExistingNewValue;
var
  mStorage: IAtlasSettingsStorage;
  mParts: IAtlasSettingsParts;
  mPart: TFakePart;
  mListener: TLogListener;
  mListenerRef: IAtlasSettingsListener;
begin
  mStorage := TAtlasMemorySettingsStorage.Create;
  mStorage.WriteText('alt', 'alter Wert');
  mStorage.WriteText('neu', 'neuer Wert');
  mParts := TAtlasSettingsParts.Create(mStorage);
  mListener := TLogListener.Create;
  mListenerRef := mListener;
  mParts.Subscribe(mListenerRef);
  mPart := TFakePart.Create('atlas.x');
  mPart.AddKey('neu', svString, '');
  mPart.AddRename('alt', 'neu');
  mParts.Add(mPart as IAtlasSettingsPart);
  Assert.AreEqual('neuer Wert', mParts.Values.ReadString('neu'));
  Assert.IsFalse(mStorage.Contains('alt'));
  // Nichts übernommen: keine Meldung scRenamed.
  Assert.AreEqual('added:atlas.x:', mListener.Text);
end;

procedure TSettingsPartsTests.RenameAppliedOnUseStorage;
var
  mStorage: IAtlasSettingsStorage;
  mParts: IAtlasSettingsParts;
  mPart: TFakePart;
  mListener: TLogListener;
  mListenerRef: IAtlasSettingsListener;
begin
  mParts := TAtlasSettingsParts.Create;
  mPart := TFakePart.Create('atlas.x');
  mPart.AddKey('neu', svInteger, '1');
  mPart.AddRename('alt', 'neu');
  mParts.Add(mPart as IAtlasSettingsPart);
  mListener := TLogListener.Create;
  mListenerRef := mListener;
  mParts.Subscribe(mListenerRef);
  mStorage := TAtlasMemorySettingsStorage.Create;
  mStorage.WriteText('alt', '8');
  mParts.UseStorage(mStorage);
  Assert.AreEqual(8, mParts.Values.ReadInteger('neu'));
  Assert.IsFalse(mStorage.Contains('alt'));
  Assert.AreEqual('storage:: renamed:atlas.x:neu<alt', mListener.Text);
end;

procedure TSettingsPartsTests.RejectsRenameOfRegisteredKey;
var
  mParts: IAtlasSettingsParts;
  mPart: TFakePart;
  mCount: Integer;
begin
  mParts := TAtlasSettingsParts.Create;
  mParts.Add(DebuggerPart as IAtlasSettingsPart);
  mCount := 0;
  // Alter Name gehört einem anderen Modul.
  mPart := TFakePart.Create('atlas.x');
  mPart.AddKey('x.depth', svInteger, '1');
  mPart.AddRename('debug.depth', 'x.depth');
  try
    mParts.Add(mPart as IAtlasSettingsPart);
  except
    on EAtlasSettingsParts do
      Inc(mCount);
  end;
  // Neuer Name ist kein eigener Schlüssel.
  mPart := TFakePart.Create('atlas.x');
  mPart.AddKey('x.depth', svInteger, '1');
  mPart.AddRename('x.alt', 'x.anders');
  try
    mParts.Add(mPart as IAtlasSettingsPart);
  except
    on EAtlasSettingsParts do
      Inc(mCount);
  end;
  Assert.AreEqual(2, mCount);
  Assert.AreEqual(1, Integer(Length(mParts.Parts)));
end;

procedure TSettingsPartsTests.ForgetOwnerRemovesEveryKeyEverRegistered;
var
  mStorage: IAtlasSettingsStorage;
  mParts: IAtlasSettingsParts;
  mOld: TFakePart;
  mRegistration: IAtlasRegistration;
begin
  mStorage := TAtlasMemorySettingsStorage.Create;
  mStorage.WriteText('fremd.wert', 'bleibt');
  mParts := TAtlasSettingsParts.Create(mStorage);
  // Frühere Version des Moduls mit einem Schlüssel, den die neue nicht mehr hat.
  mOld := TFakePart.Create('atlas.debugger');
  mOld.AddKey('debug.old', svString, '');
  mRegistration := mParts.Add(mOld as IAtlasSettingsPart);
  mParts.Values.WriteString('debug.old', 'x');
  mRegistration.Revoke;
  mRegistration := mParts.Add(DebuggerPart as IAtlasSettingsPart);
  mParts.Values.WriteInteger('debug.depth', 5);
  mParts.Values.WriteBoolean('debug.enabled', False);
  mRegistration.Revoke;
  Assert.AreEqual(3, mParts.ForgetOwner('atlas.debugger'));
  Assert.AreEqual(1, Integer(Length(mParts.Values.StoredKeys)));
  Assert.AreEqual('bleibt', mStorage.ReadText('fremd.wert'));
  Assert.IsFalse(mStorage.Contains(cAtlasOwnerKeysPrefix + 'atlas.debugger' + cAtlasOwnerKeysSuffix));
  Assert.AreEqual(0, mParts.ForgetOwner('atlas.debugger'));
end;

procedure TSettingsPartsTests.ForgetOwnerRefusesRegisteredModule;
var
  mParts: IAtlasSettingsParts;
  mRaised: Boolean;
begin
  mParts := TAtlasSettingsParts.Create;
  mParts.Add(DebuggerPart as IAtlasSettingsPart);
  mParts.Values.WriteInteger('debug.depth', 5);
  mRaised := False;
  try
    mParts.ForgetOwner('atlas.debugger');
  except
    on EAtlasSettingsParts do
      mRaised := True;
  end;
  Assert.IsTrue(mRaised);
  Assert.AreEqual(5, mParts.Values.ReadInteger('debug.depth'));
end;

procedure TSettingsPartsTests.ListenerSeesChanges;
var
  mParts: IAtlasSettingsParts;
  mListener: TLogListener;
  mListenerRef: IAtlasSettingsListener;
  mRegistration: IAtlasRegistration;
begin
  mParts := TAtlasSettingsParts.Create;
  mListener := TLogListener.Create;
  mListenerRef := mListener;
  mParts.Subscribe(mListenerRef);
  mRegistration := mParts.Add(DebuggerPart as IAtlasSettingsPart);
  mParts.Values.WriteInteger('debug.depth', 5);
  // Gleicher Wert: keine Meldung.
  mParts.Values.WriteInteger('debug.depth', 5);
  mParts.Values.Reset('debug.depth');
  // Ohne gespeicherten Wert: keine Meldung.
  mParts.Values.Reset('debug.depth');
  mRegistration.Revoke;
  mParts.ForgetOwner('atlas.debugger');
  Assert.AreEqual('added:atlas.debugger: value:atlas.debugger:debug.depth value:atlas.debugger:debug.depth ' +
    'removed:atlas.debugger: forgotten:atlas.debugger:', mListener.Text);
end;

procedure TSettingsPartsTests.RevokedListenerIsNotCalled;
var
  mParts: IAtlasSettingsParts;
  mListener: TLogListener;
  mListenerRef: IAtlasSettingsListener;
  mRegistration: IAtlasRegistration;
begin
  mParts := TAtlasSettingsParts.Create;
  mListener := TLogListener.Create;
  mListenerRef := mListener;
  mRegistration := mParts.Subscribe(mListenerRef);
  mRegistration.Revoke;
  mParts.Add(DebuggerPart as IAtlasSettingsPart);
  Assert.AreEqual('', mListener.Text);
end;

procedure TSettingsPartsTests.ModuleScopeRemovesPart;
var
  mRegistry: IAtlasModuleRegistry;
  mParts: IAtlasSettingsParts;
  mScope: IAtlasModuleScope;
begin
  mRegistry := TAtlasModuleRegistry.Create;
  mParts := TAtlasSettingsParts.Create;
  mScope := mRegistry.RegisterModule(TFakeModule.Create('atlas.debugger') as IAtlasModule);
  mScope.Own(mParts.Add(DebuggerPart as IAtlasSettingsPart));
  mParts.Values.WriteInteger('debug.depth', 6);
  mRegistry.UnregisterModule('atlas.debugger');
  Assert.AreEqual(0, Integer(Length(mParts.Parts)));
  Assert.IsTrue(mParts.Values.Contains('debug.depth'));
end;

procedure TSettingsPartsTests.MemoryStorageSortsNames;
var
  mStorage: IAtlasSettingsStorage;
  mNames: TArray<string>;
begin
  mStorage := TAtlasMemorySettingsStorage.Create;
  mStorage.WriteText('b', '2');
  mStorage.WriteText('a', '1');
  mStorage.WriteText('c', '');
  mStorage.Remove('b');
  mStorage.Remove('fehlt');
  mNames := mStorage.Names;
  Assert.AreEqual(2, Integer(Length(mNames)));
  Assert.AreEqual('a', mNames[0]);
  Assert.AreEqual('c', mNames[1]);
  Assert.IsTrue(mStorage.Contains('c'), 'leerer Wert ist ein Wert');
  Assert.AreEqual('', mStorage.ReadText('fehlt'));
end;

procedure TSettingsPartsTests.GlobalPartsExist;
var
  mFirst, mSecond: IAtlasSettingsParts;
begin
  mFirst := AtlasSettingsParts;
  mSecond := AtlasSettingsParts;
  Assert.IsTrue(mFirst <> nil);
  Assert.IsTrue(mFirst = mSecond, 'jeder Aufruf liefert dieselbe Instanz');
end;

initialization
  TDUnitX.RegisterTestFixture(TSettingsPartsTests);

end.
