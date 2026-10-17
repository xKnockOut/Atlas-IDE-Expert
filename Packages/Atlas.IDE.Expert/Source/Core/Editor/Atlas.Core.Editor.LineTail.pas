unit Atlas.Core.Editor.LineTail;

// Platz hinter dem Zeilenende (#509), ohne VCL und Open Tools API: Inlay-Hints,
// Blockende-Beschriftungen (#401, #620) und Fehlertexte (#509) zeichnen alle
// hinter das letzte Zeichen einer Zeile. Die IDE ruft die Zeichner einer Zeile
// direkt nacheinander auf, in unbekannter Reihenfolge. Jeder Zeichner fragt
// mit Start nach seinem linken Rand und meldet mit Finish, wie weit er
// gezeichnet hat; der nächste beginnt dahinter. Kommt ein Zeichner für
// dieselbe Zeile ein zweites Mal (neues Zeichnen), beginnt die Zeile neu.

interface

uses
  System.SysUtils;

type
  TAtlasLineTail = class
  public const
    /// <summary>Abstand zwischen zwei Elementen in Pixeln.</summary>
    Gap = 8;
  private
    class var FKey: string;
    class var FRight: Integer;
    class var FOwners: TArray<Pointer>;
    class function Has(AOwner: Pointer): Boolean; static;
  public
    /// <summary>Schlüssel einer gezeichneten Zeile aus Datei, Zeilen und oberem Rand.</summary>
    class function KeyOf(const AFileName: string; ALogicalLine, AEditorLine, ATop: Integer): string; static;
    /// <summary>Linker Rand für AOwner in der Zeile AKey; mindestens ABase.</summary>
    class function Start(AOwner: Pointer; const AKey: string; ABase: Integer): Integer; static;
    /// <summary>AOwner hat bis ARight gezeichnet.</summary>
    class procedure Finish(AOwner: Pointer; const AKey: string; ARight: Integer); static;
    /// <summary>Vergisst alles (Tests, Entladen).</summary>
    class procedure Reset; static;
  end;

implementation

class function TAtlasLineTail.Has(AOwner: Pointer): Boolean;
var
  Owner: Pointer;
begin
  for Owner in FOwners do
    if Owner = AOwner then
      Exit(True);
  Result := False;
end;

class function TAtlasLineTail.KeyOf(const AFileName: string; ALogicalLine, AEditorLine, ATop: Integer): string;
begin
  Result := AFileName + '|' + IntToStr(ALogicalLine) + '|' + IntToStr(AEditorLine) + '|' + IntToStr(ATop);
end;

class function TAtlasLineTail.Start(AOwner: Pointer; const AKey: string; ABase: Integer): Integer;
begin
  // Andere Zeile oder derselbe Zeichner noch einmal: die Zeile wird neu gezeichnet.
  if (AKey <> FKey) or Has(AOwner) then
  begin
    FKey := AKey;
    FRight := ABase;
    FOwners := nil;
  end;
  if FRight > ABase then
    Result := FRight
  else
    Result := ABase;
end;

class procedure TAtlasLineTail.Finish(AOwner: Pointer; const AKey: string; ARight: Integer);
begin
  if AKey <> FKey then
    Exit;
  if ARight + Gap > FRight then
    FRight := ARight + Gap;
  if not Has(AOwner) then
    FOwners := FOwners + [AOwner];
end;

class procedure TAtlasLineTail.Reset;
begin
  FKey := '';
  FRight := 0;
  FOwners := nil;
end;

end.
