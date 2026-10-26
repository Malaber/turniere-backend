"""Validate TestFlight archive identity, environment, icon, and tester eligibility."""
import plistlib
import sys
from pathlib import Path


def validate(info, options, environment):
    expected = {'production': ('re.turnie', 'AppIcon'), 'beta': ('re.turnie', 'AppIconBeta')}
    if environment not in expected:
        raise ValueError('Unknown app environment')
    bundle, icon = expected[environment]
    if info.get('CFBundleIdentifier') != bundle or info.get('TurniereEnvironment') != environment:
        raise ValueError('Archive bundle/environment does not match requested upload')
    actual_icon = info.get('CFBundleIcons', {}).get('CFBundlePrimaryIcon', {}).get('CFBundleIconName')
    if actual_icon != icon:
        raise ValueError('Archive icon does not match requested environment')
    if options.get('testFlightInternalTestingOnly') is True:
        raise ValueError('Both variants must remain eligible for external TestFlight groups')


if __name__ == '__main__':
    info_path, options_path, environment = sys.argv[1:]
    validate(plistlib.loads(Path(info_path).read_bytes()),
             plistlib.loads(Path(options_path).read_bytes()), environment)
