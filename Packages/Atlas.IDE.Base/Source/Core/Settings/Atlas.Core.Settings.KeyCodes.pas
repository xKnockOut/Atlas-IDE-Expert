unit Atlas.Core.Settings.KeyCodes;

// Bausteine der Tastenkürzel in den Vorgaben der Einstellungen (TShortCut): Umschalttasten wie scShift, scCtrl
// und scAlt und virtuelle Tasten wie VK_… in Windows. Eigene Namen, weil Core weder Winapi noch System.UITypes
// einbindet (unter FPC fehlen dort die vk-Konstanten). Buchstaben und Ziffern als Ord('A') bzw. Ord('1').

interface

const
  /// <summary>Umschalttasten eines TShortCut.</summary>
  cKeyShift = $2000;
  cKeyCtrl = $4000;
  cKeyAlt = $8000;
  /// <summary>Virtuelle Tasten (Windows VK_…).</summary>
  cKeyReturn = $0D;
  cKeySpace = $20;
  cKeyPageUp = $21;
  cKeyPageDown = $22;
  cKeyLeft = $25;
  cKeyUp = $26;
  cKeyRight = $27;
  cKeyDown = $28;
  cKeyInsert = $2D;
  cKeyDelete = $2E;
  cKeyF3 = $72;
  cKeyF7 = $76;
  cKeyF8 = $77;
  cKeyF9 = $78;
  cKeyF12 = $7B;
  /// <summary>VK_OEM_1: Ü auf deutscher Tastatur.</summary>
  cKeyOem1 = $BA;
  /// <summary>VK_OEM_PERIOD: Punkt.</summary>
  cKeyPeriod = $BE;
  /// <summary>VK_OEM_5: ^ auf deutscher Tastatur.</summary>
  cKeyOem5 = $DC;

implementation

end.
