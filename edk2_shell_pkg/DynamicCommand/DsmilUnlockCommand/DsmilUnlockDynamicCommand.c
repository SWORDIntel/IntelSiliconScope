/** @file
  DSMIL Unlock Dynamic Command Protocol Implementation
  
  Copyright (c) 2025, DSMIL Project. All rights reserved.
  SPDX-License-Identifier: BSD-2-Clause-Patent
**/

#include "DsmilUnlock.h"

EFI_SHELL_DYNAMIC_COMMAND_PROTOCOL  mDsmilUnlockDynamicCommand = {
  L"dsmil-unlock",
  DsmilUnlockCommandHandler,
  DsmilUnlockCommandGetHelp
};

// HII handle (not used, but referenced in header)
EFI_HII_HANDLE  gDsmilUnlockHiiHandle = NULL;

/**
  Entry point of DSMIL Unlock Dynamic Command.
  
  @param ImageHandle            The image handle of the process.
  @param SystemTable            The EFI System Table pointer.
  
  @retval EFI_SUCCESS           Command installed successfully.
**/
EFI_STATUS
EFIAPI
DsmilUnlockCommandInitialize (
  IN EFI_HANDLE        ImageHandle,
  IN EFI_SYSTEM_TABLE  *SystemTable
  )
{
  EFI_STATUS  Status;
  
  Status = gBS->InstallProtocolInterface (
                  &ImageHandle,
                  &gEfiShellDynamicCommandProtocolGuid,
                  EFI_NATIVE_INTERFACE,
                  &mDsmilUnlockDynamicCommand
                  );
  
  return Status;
}
