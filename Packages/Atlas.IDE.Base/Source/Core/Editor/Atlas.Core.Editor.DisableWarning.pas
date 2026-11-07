unit Atlas.Core.Editor.DisableWarning;

// Argumente der Client-Befehle „Warnung abschalten“ (#531), ohne IDE:
//   - atlas.disableWarning [uri, Zeile, Nummer, Bereich, fragen]: Das Plugin
//     fragt bei „fragen“ nach einer Begründung und ruft
//     atlas.server.disableWarning [uri, Zeile, Nummer, Bereich, Begründung].
//   - atlas.disableWarningProject [uri, Nummer, Bezeichner]: Das Plugin trägt
//     nach Rückfrage DCC_<Bezeichner> = false in die Basiskonfiguration des
//     Projekts ein (so speichert die IDE die Warnungen der Compiler-Optionen).

interface

uses
  System.SysUtils;

type
  TAtlasDisableWarningRequest = record
    Uri: string;
    Line: Integer;
    Code: string;
    Scope: string;
    AskReason: Boolean;
    /// <summary>Liest die Argumente von atlas.disableWarning; False bei unvollständigen.</summary>
    class function TryParse(const AArgumentsJson: string; out ARequest: TAtlasDisableWarningRequest): Boolean;
      static;
    /// <summary>Argumente für atlas.server.disableWarning mit der Begründung AReason.</summary>
    function ApplyArguments(const AReason: string): string;
  end;

  TAtlasDisableWarningProject = record
    Uri: string;
    Code: string;
    Identifier: string;
    /// <summary>Liest die Argumente von atlas.disableWarningProject; False ohne gültigen Bezeichner.</summary>
    class function TryParse(const AArgumentsJson: string; out ARequest: TAtlasDisableWarningProject): Boolean;
      static;
    /// <summary>Name der Projektoption, z. B. DCC_SYMBOL_DEPRECATED.</summary>
    function OptionName: string;
  end;

const
  /// <summary>Wert der Projektoption für „Warnung aus“.</summary>
  AtlasWarningOptionOff = 'false';

implementation

uses
  System.Generics.Collections,
  System.JSON;

function ArgumentsOf(const AJson: string): TJSONArray;
var
  mValue: TJSONValue;
begin
  Result := nil;
  mValue := TJSONObject.ParseJSONValue(AJson);
  if mValue is TJSONArray then
  begin
    Result := TJSONArray(mValue);
  end
  else
  begin
    mValue.Free;
  end;
end;

function IsIdentifier(const AText: string): Boolean;
var
  mIndex: Integer;
begin
  Result := AText <> '';
  for mIndex := 1 to Length(AText) do
  begin
    if not CharInSet(AText[mIndex], ['A'..'Z', '0'..'9', '_']) then
    begin
      Exit(False);
    end;
  end;
end;

{ TAtlasDisableWarningRequest }

class function TAtlasDisableWarningRequest.TryParse(const AArgumentsJson: string;
  out ARequest: TAtlasDisableWarningRequest): Boolean;
var
  mArguments: TJSONArray;
begin
  ARequest := Default(TAtlasDisableWarningRequest);
  mArguments := ArgumentsOf(AArgumentsJson);
  try
    Result := (mArguments <> nil) and (mArguments.Count >= 4);
    if not Result then
    begin
      Exit;
    end;
    ARequest.Uri := mArguments.Items[0].Value;
    ARequest.Line := StrToIntDef(mArguments.Items[1].Value, -1);
    ARequest.Code := mArguments.Items[2].Value;
    ARequest.Scope := mArguments.Items[3].Value;
    ARequest.AskReason := (mArguments.Count > 4) and (mArguments.Items[4] is TJSONBool) and
      TJSONBool(mArguments.Items[4]).AsBoolean;
    Result := (ARequest.Uri <> '') and (ARequest.Line >= 0) and (ARequest.Code <> '') and (ARequest.Scope <> '');
  finally
    mArguments.Free;
  end;
end;

function TAtlasDisableWarningRequest.ApplyArguments(const AReason: string): string;
var
  mArguments: TJSONArray;
begin
  mArguments := TJSONArray.Create;
  try
    mArguments.Add(Uri);
    mArguments.AddElement(TJSONNumber.Create(Line));
    mArguments.Add(Code);
    mArguments.Add(Scope);
    mArguments.Add(Trim(AReason));
    Result := mArguments.ToJSON;
  finally
    mArguments.Free;
  end;
end;

{ TAtlasDisableWarningProject }

class function TAtlasDisableWarningProject.TryParse(const AArgumentsJson: string;
  out ARequest: TAtlasDisableWarningProject): Boolean;
var
  mArguments: TJSONArray;
begin
  ARequest := Default(TAtlasDisableWarningProject);
  mArguments := ArgumentsOf(AArgumentsJson);
  try
    Result := (mArguments <> nil) and (mArguments.Count >= 3);
    if not Result then
    begin
      Exit;
    end;
    ARequest.Uri := mArguments.Items[0].Value;
    ARequest.Code := mArguments.Items[1].Value;
    ARequest.Identifier := UpperCase(Trim(mArguments.Items[2].Value));
    // Nur Bezeichner wie SYMBOL_DEPRECATED: Der Name wird Teil einer Projektoption.
    Result := (ARequest.Uri <> '') and IsIdentifier(ARequest.Identifier);
  finally
    mArguments.Free;
  end;
end;

function TAtlasDisableWarningProject.OptionName: string;
begin
  Result := 'DCC_' + Identifier;
end;

end.
