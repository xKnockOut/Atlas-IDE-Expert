unit Atlas.Core.Editor.CodeInsightKeys;

// Orte der Code-Insight-Schalter der IDE in der Registry (#1246). Delphi 13
// legt die Einstellungen je Code-Insight-Anbieter ab
// (<Basis>\Code Insight\Borland.EditOptions.Borland.CodeInsight.LSP.Pascal),
// Delphi 12 und älter je Quelltextart des Editors
// (<Basis>\Code Insight\Borland.EditOptions.Pascal, die IDString von
// IOTAEditOptions). Atlas schrieb bis #1246 nur den Ort von Delphi 13, unter
// Delphi 12 blieb Help Insight deshalb an, und die IDE zeigte ihren Hinweis
// neben dem Atlas-Tooltip. Zusätzlich zum Ort der Version gilt jeder
// Unterschlüssel, der den Wert schon trägt: So trifft der Schalter auch einen
// Ort, den die IDE selbst geschrieben hat.
// Die Merker (was Atlas abgeschaltet hat) gelten je Version und Ort; vorher
// teilten sich Delphi 12 und 13 einen Merker, und die eine IDE drehte zurück,
// was die andere abgeschaltet hatte.

interface

type
  TAtlasCodeInsightKeys = class
  public
    const
      /// <summary>Unter dem Basisschlüssel der IDE.</summary>
      cRoot = '\Code Insight';
      /// <summary>Ort ab Delphi 13 (BDS 37.0).</summary>
      cProviderKey = 'Borland.EditOptions.Borland.CodeInsight.LSP.Pascal';
      /// <summary>Ort bis Delphi 12 (BDS 23.0).</summary>
      cEditorKey = 'Borland.EditOptions.Pascal';
      /// <summary>Erste Hauptversion mit cProviderKey.</summary>
      cProviderVersion = 37;
    /// <summary>Versionsteil des Basisschlüssels (…\BDS\23.0 → 23.0); '' ohne.</summary>
    class function VersionText(const ABaseKey: string): string; static;
    /// <summary>Hauptversion aus dem Basisschlüssel (…\BDS\23.0 → 23); 0 ohne.</summary>
    class function MajorVersion(const ABaseKey: string): Integer; static;
    /// <summary>Unterschlüssel von cRoot, den die IDE dieser Version liest; bei unbekannter Version ''.</summary>
    class function VersionKey(const ABaseKey: string): string; static;
    /// <summary>Unterschlüssel von cRoot, die zu schalten sind: zuerst der Ort der Version (bei unbekannter beide
    /// bekannten), dann jeder aus AWithValue (Unterschlüssel, die den Wert schon tragen). Ohne Doppel.</summary>
    class function Targets(const ABaseKey: string; const AWithValue: TArray<string>): TArray<string>; static;
    /// <summary>Name des Merkers für AMarker an ASubKey unter dieser Version, z. B.
    /// "IdeHelpInsightDisabled 23.0 Borland.EditOptions.Pascal".</summary>
    class function Marker(const AMarker, ABaseKey, ASubKey: string): string; static;
    /// <summary>Gilt der alte Merker ohne Version und Ort (bis #1246) für ASubKey? Nur für den Ort, an dem Atlas
    /// damals geschrieben hat, und nur unter der Version, die ihn liest.</summary>
    class function UsesLegacyMarker(const ABaseKey, ASubKey: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils;

class function TAtlasCodeInsightKeys.VersionText(const ABaseKey: string): string;
var
  mKey: string;
  mSlash: Integer;
begin
  mKey := ABaseKey;
  while mKey.EndsWith('\') do
    mKey := mKey.Substring(0, mKey.Length - 1);
  mSlash := mKey.LastIndexOf('\');
  Result := mKey.Substring(mSlash + 1);
  if (Result = '') or not CharInSet(Result[1], ['0'..'9']) then
    Result := '';
end;

class function TAtlasCodeInsightKeys.MajorVersion(const ABaseKey: string): Integer;
var
  mText: string;
  mDot: Integer;
begin
  mText := VersionText(ABaseKey);
  mDot := mText.IndexOf('.');
  if mDot >= 0 then
    mText := mText.Substring(0, mDot);
  Result := StrToIntDef(mText, 0);
end;

class function TAtlasCodeInsightKeys.VersionKey(const ABaseKey: string): string;
var
  mMajor: Integer;
begin
  mMajor := MajorVersion(ABaseKey);
  if mMajor = 0 then
    Result := ''
  else if mMajor >= cProviderVersion then
    Result := cProviderKey
  else
    Result := cEditorKey;
end;

class function TAtlasCodeInsightKeys.Targets(const ABaseKey: string; const AWithValue: TArray<string>): TArray<string>;

  procedure Add(const AKey: string);
  var
    mKnown: string;
  begin
    if AKey = '' then
      Exit;
    for mKnown in Result do
      if SameText(mKnown, AKey) then
        Exit;
    Result := Result + [AKey];
  end;

var
  mKey: string;
begin
  Result := nil;
  if VersionKey(ABaseKey) <> '' then
    Add(VersionKey(ABaseKey))
  else
  begin
    Add(cProviderKey);
    Add(cEditorKey);
  end;
  for mKey in AWithValue do
    Add(mKey);
end;

class function TAtlasCodeInsightKeys.Marker(const AMarker, ABaseKey, ASubKey: string): string;
begin
  Result := AMarker + ' ' + VersionText(ABaseKey) + ' ' + ASubKey;
end;

class function TAtlasCodeInsightKeys.UsesLegacyMarker(const ABaseKey, ASubKey: string): Boolean;
begin
  Result := SameText(ASubKey, cProviderKey) and (MajorVersion(ABaseKey) >= cProviderVersion);
end;

end.
