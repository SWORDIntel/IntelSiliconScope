# Contributing to DSMIL Firmware Toolkit

Thank you for your interest in contributing to the DSMIL Firmware Toolkit! This document provides guidelines for contributing to this project.

## 🤝 How to Contribute

### Reporting Issues

1. **Search existing issues** - Check if the issue has already been reported
2. **Use issue templates** - Provide detailed information using the appropriate template
3. **Include system information** - OS, kernel version, hardware platform
4. **Provide logs** - Include relevant logs and error messages
5. **Steps to reproduce** - Clear reproduction steps for bugs

### Submitting Pull Requests

1. **Fork the repository** - Create a personal fork
2. **Create a feature branch** - Use descriptive branch names
3. **Make your changes** - Follow coding standards
4. **Test thoroughly** - Ensure all tests pass
5. **Submit PR** - Provide clear description of changes

## 🛠️ Development Setup

### Prerequisites

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install -y build-essential python3 python3-pip \
    clang-format cppcheck shellcheck meson ninja \
    git qemu-kvm wine64

# Python development tools
pip3 install black pylint pytest
```

### Setup Development Environment

```bash
# Clone with submodules
git clone --recursive https://github.com/dsmil/firmware-toolkit.git
cd firmware-toolkit

# Install development dependencies
make check-deps

# Build all components
make all

# Run tests
make test
```

## 📝 Coding Standards

### C Code

- Use **clang-format** for formatting (configured in `.clang-format`)
- Follow **Linux kernel coding style**
- Use **snake_case** for functions and variables
- Use **UPPER_CASE** for constants and macros
- Include proper error handling and logging

### Python Code

- Use **black** for formatting
- Follow **PEP 8** style guide
- Use **type hints** where appropriate
- Include docstrings for all functions

### Shell Scripts

- Use **shellcheck** for validation
- Follow **Google Shell Style Guide**
- Quote variables properly
- Include error handling

## 🧪 Testing

### Unit Tests

- Write tests for new functionality
- Use **pytest** for Python tests
- Use **CUnit** or similar for C tests
- Maintain >80% code coverage

### Integration Tests

- Test tool interactions
- Verify hardware compatibility
- Test error conditions
- Validate output formats

## 📋 Pull Request Process

### Before Submitting

1. **Run all tests** - `make test`
2. **Format code** - `make format`
3. **Lint code** - `make lint`
4. **Update documentation** - README, API docs
5. **Add tests** - For new functionality

### PR Template

```markdown
## Description
Brief description of changes and their purpose.

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
- [ ] Unit tests pass
- [ ] Integration tests pass
- [ ] Manual testing completed

## Hardware Tested
- [ ] Intel I219-V
- [ ] Intel I219-LM
- [ ] Other: _________

## Checklist
- [ ] Code follows style guidelines
- [ ] Self-review completed
- [ ] Documentation updated
- [ ] Tests added/updated
```

## 🔒 Security Considerations

### Code Review

- Review all firmware modification code
- Check for buffer overflows and memory leaks
- Validate input parameters
- Ensure proper privilege checks

### Testing

- Test with various hardware platforms
- Verify error handling
- Test with corrupted firmware
- Check for race conditions

## 📚 Documentation

### README Updates

- Update feature list
- Add new usage examples
- Update installation instructions
- Document breaking changes

### API Documentation

- Use docstrings for Python
- Use Doxygen for C code
- Include parameter descriptions
- Provide usage examples

## 🚀 Release Process

### Version Bump

1. Update version in `Makefile`
2. Update `CHANGELOG.md`
3. Tag release in git
4. Create release archive

### Release Checklist

- [ ] All tests pass
- [ ] Documentation updated
- [ ] Version numbers updated
- [ ] Changelog updated
- [ ] Release notes prepared
- [ ] Archive created and tested

## 🤝 Community Guidelines

### Code of Conduct

- Be respectful and inclusive
- Welcome newcomers
- Provide constructive feedback
- Focus on what is best for the community

### Communication

- Use GitHub Issues for bug reports
- Use Discussions for questions
- Be patient with responses
- Help others when possible

## 📞 Getting Help

- **GitHub Issues** - Bug reports and feature requests
- **GitHub Discussions** - Questions and general discussion
- **Documentation** - Check existing docs first
- **Examples** - Review usage examples

## 🏆 Recognition

Contributors will be recognized in:

- README.md contributors section
- Release notes
- Commit history
- Project documentation

Thank you for contributing to the DSMIL Firmware Toolkit! 🎉
