unit Ref.Pruefung.Verstoesse;

// Bewusst eingebaute Regelverstöße. Jede Zeile mit "// ERWARTET: <regel>"
// muss genau diesen Treffer liefern, Zeilen mit "// KEIN-TREFFER: <regel>"
// dürfen ihn nicht liefern. Siehe README.md. Die Verstöße mit FireDAC stehen
// in Ref.Pruefung.Datenbank (nur im optionalen Projekt RefDaten).
//
// Einige Verstöße erzeugen beim Übersetzen gewollt Hinweise oder Warnungen;
// die Liste steht in erwartete-meldungen.txt.
//
// "// ERWARTET-INDEX: <regel>" markiert Treffer von Regeln, die die RTL im
// Index brauchen (z. B. legacy-stack-queue, #1106). Der Golden-Korpus prüft
// je Datei ohne Index; diese Marker prüfen die Tests der Regel mit RTL-Stubs.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Contnrs,
  System.Generics.Collections;

type
  TPunkt = record
    X, Y: Integer;
  end;

function OhneErgebnis(AWert: Integer): Integer; // ERWARTET-PROJEKT: unused-public-member
procedure MitWith(var APunkt: TPunkt); // ERWARTET-PROJEKT: unused-public-member
procedure UngenutzteVariable; // ERWARTET-PROJEKT: unused-public-member
procedure Leck; // ERWARTET-PROJEKT: unused-public-member
procedure KeinLeck; // ERWARTET-PROJEKT: unused-public-member
procedure LeererExceptBlock; // ERWARTET-PROJEKT: unused-public-member
procedure Unerreichbar; // ERWARTET-PROJEKT: unused-public-member

implementation

type
  TKnoten = class
  end;

function OhneErgebnis(AWert: Integer): Integer; // ERWARTET: result-not-set
begin
  if AWert > 0 then
    Result := AWert;
end;

procedure MitWith(var APunkt: TPunkt);
begin
  with APunkt do // ERWARTET: with-statement
    X := Y;
end;

procedure UngenutzteVariable;
var
  Unbenutzt: Integer; // ERWARTET: unused-local
  Benutzt: Integer; // KEIN-TREFFER: unused-local
begin
  Benutzt := 1;
  if Benutzt > 0 then
    Exit;
end;

procedure Leck;
var
  Liste: TStringList;
begin
  Liste := TStringList.Create; // ERWARTET: possible-leak
  Liste.Add('x');
end;

procedure KeinLeck;
var
  Liste: TStringList;
begin
  Liste := TStringList.Create; // KEIN-TREFFER: possible-leak
  try
    Liste.Add('x');
  finally
    Liste.Free;
  end;
end;

procedure LeererExceptBlock;
begin
  try
    Abort;
  except end; // ERWARTET: empty-except
end;

procedure Unerreichbar;
begin
  Exit;
  Abort; // ERWARTET: unreachable-code
end;

function RueckwaertsSummieren(const AWerte: TArray<Integer>): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := High(AWerte) to Low(AWerte) do // ERWARTET: for-high-to-low
    Inc(Result, AWerte[I]);
end;

procedure NameUebernehmen(var AName: string);
begin
  AName := AName; // ERWARTET: self-assignment
end;

procedure Abzaehlen(var AZaehler: Integer);
var
  I: Integer;
begin
  for I := 1 to 3 do
  begin
    Inc(AZaehler, I);
    Continue; // ERWARTET: redundant-jump
  end;
  Exit; // ERWARTET: redundant-jump
end;

procedure StapelLesen;
var
  Offen: TObjectStack; // ERWARTET-INDEX: legacy-stack-queue
  Knoten: TKnoten;
begin
  Offen := TObjectStack.Create;
  try
    Offen.Push(TKnoten.Create);
    Knoten := TKnoten(Offen.Pop);
    Knoten.Free;
  finally
    Offen.Free;
  end;
end;

procedure StapelGenerisch;
var
  Fertig: TObjectStack<TKnoten>; // KEIN-TREFFER: legacy-stack-queue
begin
  Fertig := TObjectStack<TKnoten>.Create;
  try
    Fertig.Push(TKnoten.Create);
  finally
    Fertig.Free;
  end;
end;

type
  TGeraet = class
  protected
    procedure Starten(AStufe: Integer); virtual;
    procedure Stoppen; virtual;
  end;

  TDrucker = class(TGeraet)
  protected
    procedure Starten(AStufe: Integer); override;
    procedure Stoppen; override;
  public
    procedure Vorbereiten;
  end;

procedure TGeraet.Starten(AStufe: Integer);
begin
end;

procedure TGeraet.Stoppen;
begin
end;

procedure TDrucker.Starten(AStufe: Integer); // ERWARTET: override-only-inherited
begin
  inherited Starten(AStufe);
end;

procedure TDrucker.Stoppen; // KEIN-TREFFER: override-only-inherited
begin
  inherited;
  Vorbereiten;
end;

procedure TDrucker.Vorbereiten;
begin
  inherited; // ERWARTET: inherited-without-ancestor
  Stoppen;
end;

end.
