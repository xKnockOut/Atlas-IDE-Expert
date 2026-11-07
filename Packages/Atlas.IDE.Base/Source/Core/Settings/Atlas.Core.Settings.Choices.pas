unit Atlas.Core.Settings.Choices;

// Auswahllisten des Einstellungsdialogs (#227), die nicht im Schema stehen:
//   - delphiVersion: installierte Versionen als „Delphi 12 (23.0)“, gespeichert
//     wird die Registry-Nummer ("23.0").
//   - minDelphiVersion (#1126): alle bekannten Versionen, auch nicht installierte,
//     denn das Projekt muss mit ihnen übersetzen, nicht diese IDE.
//   - config und platform: aus der .dproj des Projekts (BuildConfiguration,
//     Platforms).
//   - profile und testProfile: eingebaute Profile und die eigenen aus "profiles".
// Ohne VCL und ohne Registry: Die IDE-Schicht liefert installierte Versionen
// und den Text der .dproj.

interface

uses
  System.SysUtils,
  System.JSON;

type
  /// <summary>Eintrag einer Auswahl: Anzeige und gespeicherter JSON-Text.</summary>
  TAtlasSettingChoice = record
    Caption: string;
    Json: string;
    class function Create(const ACaption, AJson: string): TAtlasSettingChoice; static;
  end;

  TAtlasSettingChoices = class
  public
    /// <summary>"Delphi 12" zu "23.0"; '' für unbekannte Nummern.</summary>
    class function DelphiProduct(const ARegistryVersion: string): string; static;
    /// <summary>"Delphi 12 (23.0)" bzw. nur die Nummer, wenn das Produkt unbekannt ist.</summary>
    class function DelphiCaption(const ARegistryVersion: string): string; static;
    /// <summary>Installierte Versionen (Registry-Nummern), neueste zuerst, ohne Doppelte.</summary>
    class function DelphiVersions(const AInstalled: TArray<string>): TArray<TAtlasSettingChoice>; static;
    /// <summary>Alle bekannten Versionen (Registry-Nummern), neueste zuerst; für minDelphiVersion (#1126).</summary>
    class function KnownVersions: TArray<string>; static;
    /// <summary>Build-Konfigurationen der .dproj ohne "Base", in der Reihenfolge der Datei.</summary>
    class function DprojConfigs(const ADprojText: string): TArray<string>; static;
    /// <summary>Aktive Plattformen der .dproj (Platform value="…" mit True).</summary>
    class function DprojPlatforms(const ADprojText: string): TArray<string>; static;
    /// <summary>Eingebaute Profile und die Namen aus "profiles" (JSON-Text eines Objekts).</summary>
    class function Profiles(const AProfilesJson: string): TArray<string>; static;
    /// <summary>Texte als Auswahl mit String-JSON.</summary>
    class function FromTexts(const ATexts: TArray<string>): TArray<TAtlasSettingChoice>; static;
    /// <summary>Index von AJson in AChoices; -1 ohne.</summary>
    class function IndexOf(const AChoices: TArray<TAtlasSettingChoice>; const AJson: string): Integer; static;
  end;

const
  /// <summary>Eingebaute Regelprofile des Servers.</summary>
  cAtlasBuiltInProfiles: array[0..4] of string = ('standard', 'fast', 'strict', 'security', 'style');

implementation

uses
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Core.Settings.JsonText;

type
  TDelphiProduct = record
    Version: string;
    Product: string;
  end;

const
  cProducts: array[0..9] of TDelphiProduct = (
    (Version: '37.0'; Product: 'Delphi 13'),
    (Version: '23.0'; Product: 'Delphi 12'),
    (Version: '22.0'; Product: 'Delphi 11'),
    (Version: '21.0'; Product: 'Delphi 10.4'),
    (Version: '20.0'; Product: 'Delphi 10.3'),
    (Version: '19.0'; Product: 'Delphi 10.2'),
    (Version: '18.0'; Product: 'Delphi 10.1'),
    (Version: '17.0'; Product: 'Delphi 10'),
    (Version: '16.0'; Product: 'Delphi XE8'),
    (Version: '15.0'; Product: 'Delphi XE7'));

function VersionNumber(const AVersion: string): Double;
var
  mSettings: TFormatSettings;
begin
  mSettings := TFormatSettings.Invariant;
  Result := StrToFloatDef(AVersion, 0, mSettings);
end;

/// <summary>Wert des Attributs AName im Tag ab APos; '' ohne.</summary>
function AttributeAfter(const AText, AName: string; APos: Integer): string;
var
  mStart, mStop, mTagEnd: Integer;
begin
  Result := '';
  mTagEnd := Pos('>', AText, APos);
  mStart := Pos(AName + '="', AText, APos);
  if (mStart = 0) or ((mTagEnd > 0) and (mStart > mTagEnd)) then
  begin
    Exit;
  end;
  Inc(mStart, Length(AName) + 2);
  mStop := Pos('"', AText, mStart);
  if mStop > mStart then
  begin
    Result := Copy(AText, mStart, mStop - mStart);
  end;
end;

procedure AddUnique(var AList: TArray<string>; const AValue: string);
var
  mItem: string;
begin
  if AValue = '' then
  begin
    Exit;
  end;
  for mItem in AList do
  begin
    if SameText(mItem, AValue) then
    begin
      Exit;
    end;
  end;
  AList := AList + [AValue];
end;

{ TAtlasSettingChoice }

class function TAtlasSettingChoice.Create(const ACaption, AJson: string): TAtlasSettingChoice;
begin
  Result.Caption := ACaption;
  Result.Json := AJson;
end;

{ TAtlasSettingChoices }

class function TAtlasSettingChoices.DelphiProduct(const ARegistryVersion: string): string;
var
  mProduct: TDelphiProduct;
begin
  Result := '';
  for mProduct in cProducts do
  begin
    if mProduct.Version = Trim(ARegistryVersion) then
    begin
      Exit(mProduct.Product);
    end;
  end;
end;

class function TAtlasSettingChoices.DelphiCaption(const ARegistryVersion: string): string;
var
  mProduct: string;
begin
  mProduct := DelphiProduct(ARegistryVersion);
  if mProduct = '' then
  begin
    Result := Trim(ARegistryVersion);
  end
  else
  begin
    Result := Format('%s (%s)', [mProduct, Trim(ARegistryVersion)]);
  end;
end;

class function TAtlasSettingChoices.KnownVersions: TArray<string>;
var
  mProduct: TDelphiProduct;
begin
  Result := nil;
  for mProduct in cProducts do
  begin
    Result := Result + [mProduct.Version];
  end;
end;

class function TAtlasSettingChoices.DelphiVersions(const AInstalled: TArray<string>): TArray<TAtlasSettingChoice>;
var
  mVersions: TArray<string>;
  mVersion: string;
  mList: TList<string>;
begin
  mVersions := nil;
  for mVersion in AInstalled do
  begin
    AddUnique(mVersions, Trim(mVersion));
  end;
  mList := TList<string>.Create(TComparer<string>.Construct(
    function(const A, B: string): Integer
    begin
      // Neueste zuerst.
      if VersionNumber(A) > VersionNumber(B) then
      begin
        Result := -1;
      end
      else if VersionNumber(A) < VersionNumber(B) then
      begin
        Result := 1;
      end
      else
      begin
        Result := CompareText(A, B);
      end;
    end));
  try
    mList.AddRange(mVersions);
    mList.Sort;
    Result := nil;
    for mVersion in mList do
    begin
      Result := Result + [TAtlasSettingChoice.Create(DelphiCaption(mVersion), TAtlasJsonText.Quote(mVersion))];
    end;
  finally
    mList.Free;
  end;
end;

class function TAtlasSettingChoices.DprojConfigs(const ADprojText: string): TArray<string>;
var
  mPosition: Integer;
  mName: string;
begin
  Result := nil;
  mPosition := Pos('<BuildConfiguration ', ADprojText);
  while mPosition > 0 do
  begin
    mName := AttributeAfter(ADprojText, 'Include', mPosition);
    if not SameText(mName, 'Base') then
    begin
      AddUnique(Result, mName);
    end;
    mPosition := Pos('<BuildConfiguration ', ADprojText, mPosition + 1);
  end;
end;

class function TAtlasSettingChoices.DprojPlatforms(const ADprojText: string): TArray<string>;
var
  mPosition, mClose, mStop: Integer;
  mName, mValue: string;
begin
  Result := nil;
  mPosition := Pos('<Platform value=', ADprojText);
  while mPosition > 0 do
  begin
    mName := AttributeAfter(ADprojText, 'value', mPosition);
    mClose := Pos('>', ADprojText, mPosition);
    mStop := Pos('</Platform>', ADprojText, mClose);
    mValue := '';
    if (mClose > 0) and (mStop > mClose) then
    begin
      mValue := Trim(Copy(ADprojText, mClose + 1, mStop - mClose - 1));
    end;
    if SameText(mValue, 'True') then
    begin
      AddUnique(Result, mName);
    end;
    mPosition := Pos('<Platform value=', ADprojText, mPosition + 1);
  end;
end;

class function TAtlasSettingChoices.Profiles(const AProfilesJson: string): TArray<string>;
var
  mName: string;
  mValue: TJSONValue;
  mPair: TJSONPair;
begin
  Result := nil;
  for mName in cAtlasBuiltInProfiles do
  begin
    AddUnique(Result, mName);
  end;
  if AProfilesJson = '' then
  begin
    Exit;
  end;
  mValue := TJSONObject.ParseJSONValue(AProfilesJson);
  try
    if mValue is TJSONObject then
    begin
      for mPair in TJSONObject(mValue) do
      begin
        AddUnique(Result, mPair.JsonString.Value);
      end;
    end;
  finally
    mValue.Free;
  end;
end;

class function TAtlasSettingChoices.FromTexts(const ATexts: TArray<string>): TArray<TAtlasSettingChoice>;
var
  mText: string;
begin
  Result := nil;
  for mText in ATexts do
  begin
    Result := Result + [TAtlasSettingChoice.Create(mText, TAtlasJsonText.Quote(mText))];
  end;
end;

class function TAtlasSettingChoices.IndexOf(const AChoices: TArray<TAtlasSettingChoice>; const AJson: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AChoices) do
  begin
    if AChoices[mIndex].Json = AJson then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

end.
