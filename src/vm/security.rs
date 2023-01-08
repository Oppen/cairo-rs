use super::{
    errors::{
        memory_errors::MemoryError, runner_errors::RunnerError, vm_errors::VirtualMachineError,
    },
    runners::cairo_runner::CairoRunner,
    vm_core::VirtualMachine,
    vm_memory::memory::MaybeAccessed,
};
use crate::types::relocatable::Relocatable;
use std::{collections::HashMap, mem::swap};

/// Verify that the completed run in a runner is safe to be relocated and be
/// used by other Cairo programs.
///
/// Checks include:
///   - There mustn't be memory accesses to any temporary segment.
///   - All accesses to the builtin segments must be within the range defined by
///     the builtins themselves.
///   - There mustn't be accesses to the program segment outside the program
///     data range.
///
/// Note: Each builtin is responsible for checking its own segments' data.
pub fn verify_secure_runner(
    runner: &CairoRunner,
    verify_builtins: bool,
    vm: &mut VirtualMachine,
) -> Result<(), VirtualMachineError> {
    let program_base = runner
        .program_base
        .as_ref()
        .ok_or(RunnerError::NoProgBase)?;

    let builtin_segments = match verify_builtins {
        true => runner.get_builtin_segments_info(vm)?,
        false => HashMap::new(),
    };

    let builtin_segment_by_index = builtin_segments
        .iter()
        .map(|(seg_name, seg_info)| (seg_info.index, (seg_name, seg_info)))
        .collect::<HashMap<_, _>>();

    let memory_iter = vm
        .memory
        .data
        .iter()
        .enumerate()
        .flat_map(|(idx, segment)| {
            segment.iter().enumerate().filter_map(move |(off, value)| {
                value
                    .as_ref()
                    .map(|val| (Relocatable::from((idx as _, off)), val))
            })
        });
    for (addr, value) in memory_iter {
        // Check builtin segment bounds.
        if let Some((_, seg_info)) = builtin_segment_by_index.get(&addr.segment_index) {
            if addr.offset >= seg_info.size {
                return Err(RunnerError::FailedMemoryGet(MemoryError::NumOutOfBounds).into());
            }
        }

        // Check program segment bounds.
        if addr.segment_index == program_base.segment_index
            && addr.offset >= runner.program.data.len()
        {
            return Err(RunnerError::FailedMemoryGet(MemoryError::NumOutOfBounds).into());
        }

        let value = match value {
            MaybeAccessed::Hole(ref value) | MaybeAccessed::Accessed(ref value) => value,
        };

        // Check value validity (when relocatable, that the segment exists and
        // is not temporary).
        if !vm
            .segments
            .is_valid_memory_value(value)
            .map_err(RunnerError::FailedMemoryGet)?
        {
            return Err(
                RunnerError::FailedMemoryGet(MemoryError::InvalidMemoryValue(addr, value.clone()))
                    .into(),
            );
        }
    }

    // This swap is needed to avoid double mutable borrows.
    let mut tmp = Vec::new();
    swap(&mut tmp, &mut vm.builtin_runners);
    for (_, builtin_runner) in &tmp {
        builtin_runner.run_security_checks(vm)?;
    }
    swap(&mut tmp, &mut vm.builtin_runners);

    Ok(())
}

#[cfg(test)]
mod test {
    use super::*;
    use crate::{relocatable, types::program::Program, utils::test_utils::*};
    use felt::Felt;
    use num_traits::Zero;

    #[test]
    fn verify_secure_runner_without_program_base() {
        let program = program!();

        let runner = cairo_runner!(program);
        let mut vm = vm!();

        assert_eq!(
            verify_secure_runner(&runner, true, &mut vm),
            Err(RunnerError::NoProgBase.into()),
        );
    }

    #[test]
    fn verify_secure_runner_empty_memory() {
        let program = program!(main = Some(0),);

        let mut runner = cairo_runner!(program);
        let mut vm = vm!();

        runner.initialize(&mut vm).unwrap();
        vm.segments.compute_effective_sizes(&vm.memory);
        assert_eq!(verify_secure_runner(&runner, true, &mut vm), Ok(()));
    }

    #[test]
    fn verify_secure_runner_program_out_of_bounds() {
        let program = program!(main = Some(0),);

        let mut runner = cairo_runner!(program);
        let mut vm = vm!();

        runner.initialize(&mut vm).unwrap();

        vm.memory.data = vec![vec![Some(relocatable!(0, 1000).into())]];
        vm.segments.segment_used_sizes = Some(vec![0, 0, 0, 0]);

        assert_eq!(
            verify_secure_runner(&runner, true, &mut vm),
            Err(RunnerError::FailedMemoryGet(MemoryError::NumOutOfBounds).into())
        );
    }

    #[test]
    fn verify_secure_runner_success() {
        let program = program!(
            data = vec![
                Felt::zero().into(),
                Felt::zero().into(),
                Felt::zero().into(),
                Felt::zero().into(),
            ],
            main = Some(0),
        );

        let mut runner = cairo_runner!(program);
        let mut vm = vm!();

        runner.initialize(&mut vm).unwrap();

        vm.memory.data = vec![vec![
            Some(relocatable!(1, 0).into()),
            Some(relocatable!(2, 1).into()),
            Some(relocatable!(3, 2).into()),
            Some(relocatable!(4, 3).into()),
        ]];
        vm.segments.segment_used_sizes = Some(vec![5, 1, 2, 3, 4]);

        assert_eq!(verify_secure_runner(&runner, true, &mut vm), Ok(()));
    }
}
